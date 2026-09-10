"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useAccount, useChainId, usePublicClient, useWalletClient } from "wagmi";
import { formatBaseUnits, parseDecimal } from "@/amounts";
import { ApiClient } from "@/api/client";
import { browserAbis, type ReviewedDeployment } from "@/contracts/generated";
import { publicConfiguration } from "@/config/public";
import { useWalletReadiness } from "@/wallet/readiness";
import {
  calculateLaunchValue,
  claimIsExecutable,
  decodeTransactionError,
  minimumOutput,
  reviewedRouterAddress,
  sameWriteIntent,
  transactionDeadline,
  validateLaunchInput,
  type TransactionState,
  createTransactionState,
  transitionTransaction,
} from "@/transactions";
import {
  Badge,
  Button,
  ErrorState,
  Input,
  SafeImage,
  UnavailableState,
} from "@/components/primitives";

const DEFAULT_TTL = 900n;
type Address = `0x${string}`;

function eth(value: bigint) {
  return `${formatBaseUnits(value, 18, 6)} ETH`;
}

function safeAddress(value: string | null | undefined): Address | null {
  return value && /^0x[0-9a-fA-F]{40}$/.test(value) ? (value as Address) : null;
}

function statusLabel(status: TransactionState["status"]) {
  return status === "awaiting-signature"
    ? "Awaiting signature"
    : status.charAt(0).toUpperCase() + status.slice(1);
}

function currentUnixSeconds() {
  return BigInt(Math.floor(Date.now() / 1000));
}

function ErrorCopy({ error }: { error: unknown }) {
  const decoded = decodeTransactionError(error);
  return (
    <p className="transaction-error" role="alert">
      {decoded.message}
    </p>
  );
}

function ReadinessGate({ children }: { children: React.ReactNode }) {
  const configuration = publicConfiguration();
  if (configuration.status !== "ready")
    return (
      <UnavailableState
        title="Transactions unavailable"
        description="A reviewed deployment, RPC endpoint, API, and wallet configuration are required. No transaction can be submitted."
      />
    );
  return <>{children}</>;
}

export function TradingPanel({
  token,
}: {
  token: {
    address: string;
    curve: string;
    pair: string;
    phase: string;
    name: string;
    symbol: string;
  };
}) {
  return (
    <ReadinessGate>
      <TradingPanelReady token={token} />
    </ReadinessGate>
  );
}

function TradingPanelReady({
  token,
}: {
  token: {
    address: string;
    curve: string;
    pair: string;
    phase: string;
    name: string;
    symbol: string;
  };
}) {
  const tokenAddress = safeAddress(token.address);
  const curveAddress = safeAddress(token.curve);
  const safeTokenAddress =
    tokenAddress ?? ("0x0000000000000000000000000000000000000000" as Address);
  const safeCurveAddress =
    curveAddress ?? ("0x0000000000000000000000000000000000000000" as Address);
  const [side, setSide] = useState<"buy" | "sell">("buy");
  const [input, setInput] = useState("");
  const [slippage, setSlippage] = useState("5");
  const [quote, setQuote] = useState<{
    output: bigint;
    fee: bigint;
    source: "backend" | "contract";
  } | null>(null);
  const [quoteError, setQuoteError] = useState<string | null>(null);
  const [confirming, setConfirming] = useState(false);
  const [state, setState] = useState<TransactionState>(createTransactionState("disconnected"));
  const [approvalHash, setApprovalHash] = useState<Address | undefined>();
  const intentRef = useRef<import("@/transactions").ExactWrite | null>(null);
  const configuration = publicConfiguration();
  const readiness = useWalletReadiness();
  const account = useAccount();
  const chainId = useChainId();
  const publicClient = usePublicClient();
  const { data: walletClient } = useWalletClient();
  const reviewedRouter = reviewedRouterAddress(configuration.deployment!, configuration.chainId);
  const graduated = token.phase.toLowerCase() === "graduated";
  const claimsEligible = claimIsExecutable({
    serverEligible: false,
    onChainEligible: false,
    selectedWalletReady: readiness.selectedAccountVerified,
  });
  const decimals = 18;
  const inputUnits = useMemo(() => {
    try {
      return input.trim() ? parseDecimal(input, decimals) : null;
    } catch {
      return null;
    }
  }, [input]);
  const slippageBps = useMemo(() => {
    try {
      return parseDecimal(slippage, 2);
    } catch {
      return null;
    }
  }, [slippage]);

  useEffect(() => {
    let cancelled = false;
    if (
      !inputUnits ||
      inputUnits <= 0n ||
      configuration.status !== "ready" ||
      !configuration.apiBaseUrl
    )
      return;
    const client = new ApiClient({ baseUrl: configuration.apiBaseUrl });
    void client
      .getQuote(token.address, { amount: inputUnits.toString(), side })
      .then((result) => {
        if (!cancelled) {
          const output = BigInt(result.output);
          setQuote({
            output,
            fee: BigInt(result.protocol_fee) + BigInt(result.creator_fee),
            source: "backend",
          });
          setQuoteError(null);
        }
      })
      .catch(() => {
        if (!cancelled) {
          setQuote(null);
          setQuoteError("Informational quote unavailable. Refresh before trading.");
        }
      });
    return () => {
      cancelled = true;
    };
  }, [configuration.apiBaseUrl, configuration.status, inputUnits, side, token.address]);

  const activeQuote = inputUnits && inputUnits > 0n ? quote : null;
  const minimum =
    activeQuote && slippageBps !== null ? minimumOutput(activeQuote.output, slippageBps) : null;
  const switchNetwork = () => void readiness.switchNetwork();
  const execute = async () => {
    if (graduated) return;
    if (
      state.status !== "disconnected" &&
      state.status !== "reverted" &&
      state.status !== "rejected-signature" &&
      state.status !== "rpc-failure"
    )
      return;
    if (
      !account.address ||
      !publicClient ||
      !walletClient ||
      !minimum ||
      !inputUnits ||
      slippageBps === null ||
      chainId !== configuration.chainId ||
      !readiness.selectedAccountVerified
    ) {
      setState({ status: chainId !== configuration.chainId ? "wrong-chain" : "disconnected" });
      return;
    }
    const accountAddress = account.address;
    const now = currentUnixSeconds();
    const deadline = transactionDeadline(now, DEFAULT_TTL);
    try {
      setState(
        transitionTransaction(
          createTransactionState("disconnected"),
          { type: "validate" },
          readiness.transactionReadiness,
        ),
      );
      const phase = await publicClient.readContract({
        address: safeCurveAddress,
        abi: browserAbis.curve,
        functionName: "phase",
      });
      if (Number(phase) !== 0) throw new Error("WrongPhase");
      const tokenBalance = await publicClient.readContract({
        address: safeTokenAddress,
        abi: browserAbis.token,
        functionName: "balanceOf",
        args: [accountAddress],
      });
      if (side === "sell" && tokenBalance < inputUnits) throw new Error("ERC20InsufficientBalance");
      if (side === "buy") await publicClient.getBalance({ address: accountAddress });
      const contractQuote =
        side === "buy"
          ? await publicClient.readContract({
              address: safeCurveAddress,
              abi: browserAbis.curve,
              functionName: "quoteBuy",
              args: [inputUnits],
            })
          : await publicClient.readContract({
              address: safeCurveAddress,
              abi: browserAbis.curve,
              functionName: "quoteSell",
              args: [inputUnits],
            });
      const contractOutput =
        side === "buy"
          ? BigInt((contractQuote as readonly unknown[])[1] as bigint)
          : BigInt((contractQuote as readonly unknown[])[0] as bigint);
      const exactMinimum = minimumOutput(contractOutput, slippageBps);
      const target = safeCurveAddress;
      const args =
        side === "buy"
          ? ([accountAddress, accountAddress, exactMinimum, deadline] as const)
          : ([inputUnits, accountAddress, exactMinimum, deadline] as const);
      const value = side === "buy" ? inputUnits : 0n;
      const intent = {
        account: accountAddress,
        target,
        value,
        args,
        deadline,
        minimumOutput: exactMinimum,
      };
      intentRef.current = intent;
      setQuote({ output: contractOutput, fee: 0n, source: "contract" });
      if (side === "sell") {
        const allowance = await publicClient.readContract({
          address: safeTokenAddress,
          abi: browserAbis.token,
          functionName: "allowance",
          args: [accountAddress, safeCurveAddress],
        });
        if (allowance < inputUnits) {
          setState({ status: "simulating" });
          const approvalArgs = [safeCurveAddress, inputUnits] as const;
          await publicClient.simulateContract({
            address: safeTokenAddress,
            abi: browserAbis.token,
            functionName: "approve",
            account: accountAddress,
            args: approvalArgs,
          } as never);
          setState({ status: "awaiting-signature" });
          const hash = await walletClient.writeContract({
            address: safeTokenAddress,
            abi: browserAbis.token,
            functionName: "approve",
            account: accountAddress,
            args: approvalArgs,
          } as never);
          setApprovalHash(hash as Address);
          setState({ status: "submitted", hash: hash as Address });
          await publicClient.waitForTransactionReceipt({ hash });
          setState({ status: "mined", hash: hash as Address });
          setState({ status: "disconnected" });
          return;
        }
      }
      setState(
        transitionTransaction(
          createTransactionState("validating"),
          { type: "simulate" },
          readiness.transactionReadiness,
        ),
      );
      await publicClient.simulateContract({
        address: target,
        abi: browserAbis.curve,
        functionName: side,
        account: accountAddress,
        args,
        value,
      } as never);
      setState(
        transitionTransaction(
          createTransactionState("simulating"),
          { type: "await-signature" },
          readiness.transactionReadiness,
        ),
      );
      if (!sameWriteIntent(intent, intentRef.current!))
        throw new Error("Write intent changed; retry safely.");
      const hash = await walletClient.writeContract({
        address: target,
        abi: browserAbis.curve,
        functionName: side,
        account: accountAddress,
        args,
        value,
      } as never);
      setState({ status: "submitted", hash: hash as Address });
      await publicClient.waitForTransactionReceipt({ hash });
      setState({ status: "mined", hash: hash as Address });
      setState({ status: "indexing", hash: hash as Address });
    } catch (error) {
      const message =
        error instanceof Error && /User rejected|denied|reject/i.test(error.message)
          ? "rejected-signature"
          : "reverted";
      setState({ status: message, hash: state.hash, error: decodeTransactionError(error).message });
    }
  };
  const canSubmit = Boolean(
    inputUnits &&
    inputUnits > 0n &&
    minimum &&
    readiness.selectedAccountVerified &&
    chainId === configuration.chainId &&
    !confirming,
  );
  if (!tokenAddress || !curveAddress)
    return (
      <UnavailableState
        title="Trading unavailable"
        description="The indexed token contract address is not valid for this reviewed deployment."
      />
    );
  if (graduated)
    return (
      <section
        className="workspace-panel transaction-panel"
        aria-labelledby="graduated-trade-title"
      >
        <div className="panel-head">
          <div>
            <p className="panel-kicker">Graduated route</p>
            <h2 id="graduated-trade-title">Router handoff</h2>
          </div>
          <Badge tone="success">Graduated</Badge>
        </div>
        {reviewedRouter ? (
          <>
            <p className="transaction-risk">
              This token now trades through the reviewed Uniswap v2 router only. Approvals and
              signatures remain in your wallet.
            </p>
            <div className="quote-summary">
              <span>
                Reviewed router <strong className="mono">{reviewedRouter}</strong>
              </span>
              <small>
                Router execution is withheld until a complete pool route, WETH address, and live
                contract reads are available.
              </small>
            </div>
          </>
        ) : (
          <UnavailableState
            title="Router unavailable"
            description="No enabled reviewed Uniswap v2 router is configured for this chain. Trading is safely disabled."
          />
        )}
      </section>
    );
  return (
    <section className="workspace-panel transaction-panel" aria-labelledby="trade-title">
      <div className="panel-head">
        <div>
          <p className="panel-kicker">Wallet action</p>
          <h2 id="trade-title">Trade {token.symbol}</h2>
        </div>
        <Badge tone={token.phase === "graduated" ? "success" : "accent"}>{token.phase}</Badge>
      </div>
      {chainId !== configuration.chainId ? (
        <div className="transaction-warning" role="alert">
          Wrong network. Switch to {configuration.deployment?.name ?? "the reviewed network"} before
          signing.
          <Button size="sm" onClick={switchNetwork}>
            Switch network
          </Button>
        </div>
      ) : null}
      <div className="trade-tabs" role="tablist" aria-label="Trade side">
        <button
          type="button"
          role="tab"
          aria-selected={side === "buy"}
          className={side === "buy" ? "is-active" : ""}
          onClick={() => {
            setSide("buy");
            setInput("");
            setConfirming(false);
          }}
        >
          Buy
        </button>
        <button
          type="button"
          role="tab"
          aria-selected={side === "sell"}
          className={side === "sell" ? "is-active" : ""}
          onClick={() => {
            setSide("sell");
            setInput("");
            setConfirming(false);
          }}
        >
          Sell
        </button>
      </div>
      <div className="transaction-form">
        <Input
          label={side === "buy" ? "ETH input" : `${token.symbol} input`}
          value={input}
          onChange={(event) => {
            setInput(event.target.value);
            setConfirming(false);
          }}
          inputMode="decimal"
          placeholder="0.00"
          hint="Integer base units are used for signing; decimals are presentation only."
        />
        <Input
          label="Slippage tolerance (%)"
          value={slippage}
          onChange={(event) => setSlippage(event.target.value)}
          inputMode="decimal"
          hint="Minimum output is rounded down on-chain."
        />
        {quoteError ? (
          <p className="transaction-error" role="alert">
            {quoteError}
          </p>
        ) : null}
        {quote ? (
          <div className="quote-summary">
            <span>
              Estimated output{" "}
              <strong className="mono">{formatBaseUnits(quote.output, 18, 6)}</strong>
            </span>
            <span>
              Fees <strong className="mono">{eth(quote.fee)}</strong>
            </span>
            <span>
              Minimum output{" "}
              <strong className="mono">{minimum ? formatBaseUnits(minimum, 18, 6) : "—"}</strong>
            </span>
            <small>
              {quote.source === "backend"
                ? "Informational API quote; contract quote is authoritative before signing."
                : "Authoritative contract quote, read immediately before simulation."}
            </small>
          </div>
        ) : null}
      </div>
      <p className="transaction-risk">
        Non-custodial: your selected wallet signs directly. Transactions are irreversible and may
        lose value. Contract <span className="mono">{token.curve}</span>.
      </p>
      {confirming ? (
        <div className="transaction-confirmation" role="region" aria-label="Trade confirmation">
          <h3>Confirm {side}</h3>
          <dl>
            <dt>Token</dt>
            <dd>
              {token.name} ({token.symbol})
            </dd>
            <dt>Input</dt>
            <dd className="mono">
              {input} · {side === "buy" ? "ETH" : token.symbol}
            </dd>
            <dt>Minimum output</dt>
            <dd className="mono">{minimum ? formatBaseUnits(minimum, 18, 6) : "—"}</dd>
            <dt>Deadline</dt>
            <dd className="mono">15 minutes after the final chain read</dd>
            <dt>Network</dt>
            <dd>{configuration.deployment?.name}</dd>
          </dl>
          <div className="transaction-actions">
            <Button variant="quiet" onClick={() => setConfirming(false)}>
              Back
            </Button>
            <Button
              variant="primary"
              loading={state.status === "simulating" || state.status === "awaiting-signature"}
              disabled={!canSubmit}
              onClick={() => void execute()}
            >
              Sign {side}
            </Button>
          </div>
        </div>
      ) : (
        <Button
          variant="primary"
          size="lg"
          disabled={!canSubmit}
          onClick={() => setConfirming(true)}
        >
          {side === "sell" && approvalHash ? "Resume sell" : `Review ${side}`}
        </Button>
      )}
      {state.status !== "disconnected" ? (
        <div className="transaction-progress" role="status">
          <Badge
            tone={
              state.status === "reverted" || state.status === "rejected-signature"
                ? "danger"
                : state.status === "indexing"
                  ? "warning"
                  : "success"
            }
          >
            {statusLabel(state.status)}
          </Badge>
          {state.hash ? <span className="mono">{state.hash}</span> : null}
          {state.error ? <ErrorCopy error={new Error(state.error)} /> : null}
        </div>
      ) : null}
      <div className="claim-row">
        <span>
          Creator/refund claims require server and on-chain eligibility for this linked wallet.
        </span>
        <Button size="sm" disabled={!claimsEligible}>
          Claim
        </Button>
      </div>
    </section>
  );
}

export function LaunchPanel() {
  return (
    <ReadinessGate>
      <LaunchPanelReady />
    </ReadinessGate>
  );
}

function LaunchPanelReady() {
  const configuration = publicConfiguration();
  const readiness = useWalletReadiness();
  const account = useAccount();
  const publicClient = usePublicClient();
  const { data: walletClient } = useWalletClient();
  const [name, setName] = useState("");
  const [symbol, setSymbol] = useState("");
  const [imageUrl, setImageUrl] = useState("");
  const [xUrl, setXUrl] = useState("");
  const [telegramUrl, setTelegramUrl] = useState("");
  const [buy, setBuy] = useState("0");
  const [confirming, setConfirming] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [state, setState] = useState<TransactionState>(createTransactionState("disconnected"));
  const [launchFee, setLaunchFee] = useState<bigint | null>(null);
  const deployment = configuration.deployment as ReviewedDeployment;
  useEffect(() => {
    if (!publicClient || !deployment.factory) return;
    void publicClient
      .readContract({
        address: deployment.factory as Address,
        abi: browserAbis.factory,
        functionName: "launchFee",
      })
      .then((value) => setLaunchFee(value as bigint))
      .catch(() => setError("Factory configuration unavailable; launching is disabled."));
  }, [deployment.factory, publicClient]);
  const buyUnits = useMemo(() => {
    try {
      return parseDecimal(buy || "0");
    } catch {
      return null;
    }
  }, [buy]);
  const value =
    launchFee !== null && buyUnits !== null ? calculateLaunchValue(launchFee, buyUnits) : null;
  const validMetadata = validateLaunchInput({
    name,
    symbol,
    imageUrl,
    xUrl,
    telegramUrl,
    developerBuyGross: buyUnits ?? -1n,
  });
  const submit = async () => {
    if (
      Object.keys(validMetadata).length ||
      !publicClient ||
      !walletClient ||
      !account.address ||
      !deployment.factory ||
      value === null ||
      launchFee === null ||
      !readiness.selectedAccountVerified
    )
      return;
    try {
      setState(
        transitionTransaction(
          createTransactionState("disconnected"),
          { type: "validate" },
          readiness.transactionReadiness,
        ),
      );
      const deadline = transactionDeadline(currentUnixSeconds(), DEFAULT_TTL);
      const args = [
        {
          name: name.trim(),
          symbol: symbol.trim(),
          engineVersion: 1,
          developerBuyGross: buyUnits!,
          minDeveloperTokensOut: 0n,
          deadline,
        },
      ] as const;
      await publicClient.simulateContract({
        address: deployment.factory as Address,
        abi: browserAbis.factory,
        functionName: "launch",
        account: account.address,
        args,
        value,
      } as never);
      setState({ status: "awaiting-signature" });
      const hash = await walletClient.writeContract({
        address: deployment.factory as Address,
        abi: browserAbis.factory,
        functionName: "launch",
        account: account.address,
        args,
        value,
      } as never);
      setState({ status: "submitted", hash: hash as Address });
      await publicClient.waitForTransactionReceipt({ hash });
      setState({ status: "indexing", hash: hash as Address });
    } catch (cause) {
      setState({ status: "reverted", error: decodeTransactionError(cause).message });
    }
  };
  return (
    <section
      className="workspace-panel transaction-panel launch-panel"
      aria-labelledby="launch-title"
    >
      <div className="panel-head">
        <div>
          <p className="panel-kicker">Launch desk</p>
          <h2 id="launch-title">Create a token</h2>
        </div>
        <Badge tone="accent">Fixed supply</Badge>
      </div>
      {error ? (
        <ErrorState title="Launch unavailable" description={error} />
      ) : (
        <>
          <div className="transaction-form">
            <Input
              label="Token name"
              value={name}
              onChange={(event) => setName(event.target.value)}
              maxLength={64}
              placeholder="A clear name"
            />
            <Input
              label="Symbol"
              value={symbol}
              onChange={(event) => setSymbol(event.target.value.toUpperCase())}
              maxLength={16}
              placeholder="TICKER"
            />
            <Input
              label="Image URL (optional)"
              value={imageUrl}
              onChange={(event) => setImageUrl(event.target.value)}
              placeholder="https://…"
            />
            <Input
              label="X URL (optional)"
              value={xUrl}
              onChange={(event) => setXUrl(event.target.value)}
              placeholder="https://x.com/…"
            />
            <Input
              label="Telegram URL (optional)"
              value={telegramUrl}
              onChange={(event) => setTelegramUrl(event.target.value)}
              placeholder="https://t.me/…"
            />
            <Input
              label="Developer buy (ETH, optional)"
              value={buy}
              onChange={(event) => setBuy(event.target.value)}
              inputMode="decimal"
              hint="Launch value is exactly launch fee + developer buy gross."
            />
            {imageUrl ? (
              <SafeImage
                src={imageUrl}
                alt="Token image preview"
                className="launch-image-preview"
              />
            ) : null}
          </div>
          <div className="quote-summary">
            <span>
              Factory launch fee{" "}
              <strong className="mono">
                {launchFee === null ? "Unavailable" : eth(launchFee)}
              </strong>
            </span>
            <span>
              Exact launch value{" "}
              <strong className="mono">{value === null ? "Unavailable" : eth(value)}</strong>
            </span>
          </div>
          <p className="transaction-risk">
            Non-custodial: your selected wallet signs directly. Launch is irreversible and may lose
            value. Metadata links and image preview are validated before this confirmation step.
          </p>
          {confirming ? (
            <div className="transaction-confirmation">
              <h3>Confirm launch</h3>
              <dl>
                <dt>Token</dt>
                <dd>
                  {name || "—"} ({symbol || "—"})
                </dd>
                <dt>Launch value</dt>
                <dd className="mono">{value === null ? "Unavailable" : eth(value)}</dd>
                <dt>Network</dt>
                <dd>{deployment.name}</dd>
                <dt>Contract</dt>
                <dd className="mono">{deployment.factory}</dd>
                <dt>Deadline</dt>
                <dd className="mono">15 minutes after final reads</dd>
              </dl>
              <div className="transaction-actions">
                <Button variant="quiet" onClick={() => setConfirming(false)}>
                  Back
                </Button>
                <Button
                  variant="primary"
                  loading={state.status === "awaiting-signature"}
                  onClick={() => void submit()}
                >
                  Sign launch
                </Button>
              </div>
            </div>
          ) : (
            <Button
              variant="primary"
              size="lg"
              disabled={
                Object.keys(validMetadata).length > 0 ||
                value === null ||
                !readiness.selectedAccountVerified
              }
              onClick={() => setConfirming(true)}
            >
              Review launch
            </Button>
          )}
        </>
      )}
      {state.status !== "disconnected" ? (
        <div className="transaction-progress" role="status">
          <Badge tone={state.status === "reverted" ? "danger" : "warning"}>
            {statusLabel(state.status)}
          </Badge>
          {state.hash ? <span className="mono">{state.hash}</span> : null}
          {state.error ? <ErrorCopy error={new Error(state.error)} /> : null}
        </div>
      ) : null}
    </section>
  );
}
