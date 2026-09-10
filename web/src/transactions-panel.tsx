"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { parseEventLogs } from "viem";
import { useAccount, useConnect, usePublicClient, useWalletClient } from "wagmi";
import { formatBaseUnits, parseDecimal } from "@/amounts";
import { ApiClient } from "@/api/client";
import { browserAbis, type ReviewedDeployment } from "@/contracts/generated";
import { publicConfiguration } from "@/config/public";
import { addressExplorerUrl } from "@/wallet/explorer";
import { useWalletReadiness } from "@/wallet/readiness";
import {
  calculateLaunchValue,
  classifyTransactionFailure,
  decodeTransactionError,
  minimumOutput,
  observeCanonicalTransaction,
  parseRuntimeQuantity,
  parseSlippageBps,
  parseQuoteQuantity,
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

async function observeFreshSnapshot(
  baseUrl: string | null,
  tokenAddress: string,
  action: import("@/transactions").CanonicalObservationAction,
  state: TransactionState,
  setState: (next: TransactionState) => void,
) {
  if (!baseUrl) return;
  const client = new ApiClient({ baseUrl });
  const delays = [500, 1_000, 2_000, 4_000, 8_000, 15_000];
  const monitorDurationMs = 60_000;
  const startedAt = Date.now();
  let observedState = state;
  let attempt = 0;
  let inFlight = false;
  let timer: number | undefined;
  let stopped = false;

  const stop = () => {
    if (stopped) return;
    stopped = true;
    if (timer !== undefined) window.clearTimeout(timer);
    window.removeEventListener("launchpad:canonical-reorg", refreshOnSignal);
    window.removeEventListener("focus", refreshOnSignal);
    window.removeEventListener("online", refreshOnSignal);
    window.removeEventListener("pageshow", refreshOnSignal);
    document.removeEventListener("visibilitychange", refreshOnSignal);
  };
  const schedule = () => {
    if (stopped) return;
    const remaining = monitorDurationMs - (Date.now() - startedAt);
    if (remaining <= 0) {
      stop();
      return;
    }
    const delay = Math.min(delays[Math.min(attempt++, delays.length - 1)] ?? 15_000, remaining);
    timer = window.setTimeout(() => {
      timer = undefined;
      void refresh();
    }, delay);
  };
  const refresh = async () => {
    if (stopped || inFlight || Date.now() - startedAt >= monitorDurationMs) {
      if (!inFlight) stop();
      return;
    }
    inFlight = true;
    try {
      const fresh = await client.getCanonicalTransaction(observedState.hash ?? "");
      const records = (fresh.events ?? []).map((event) => ({
        tx_hash: event.tx_hash,
        launch_tx_hash: event.kind === "token_launch" ? event.tx_hash : undefined,
        finality: event.finality,
      }));
      const next = observeCanonicalTransaction({
        state: observedState,
        submittedHash: observedState.hash ?? "",
        action,
        records,
        snapshotFinality: fresh.finality,
      });
      const wasCanonical = ["indexed", "safe", "finalized"].includes(observedState.status);
      setState(next);
      observedState = next;
      if (next.status === "indexing" && wasCanonical)
        window.dispatchEvent(
          new CustomEvent("launchpad:canonical-reorg", { detail: { tokenAddress } }),
        );
    } catch {
      const wasCanonical = ["indexed", "safe", "finalized"].includes(observedState.status);
      const next = observeCanonicalTransaction({
        state: observedState,
        submittedHash: observedState.hash ?? "",
        action,
        records: [],
      });
      setState(next);
      if (next.status === "indexing" && wasCanonical) {
        window.dispatchEvent(
          new CustomEvent("launchpad:canonical-reorg", { detail: { tokenAddress } }),
        );
      }
      observedState = next;
    } finally {
      inFlight = false;
      schedule();
    }
  };
  const refreshOnSignal = () => {
    if (document.visibilityState === "hidden") return;
    void refresh();
  };
  window.addEventListener("launchpad:canonical-reorg", refreshOnSignal);
  window.addEventListener("focus", refreshOnSignal);
  window.addEventListener("online", refreshOnSignal);
  window.addEventListener("pageshow", refreshOnSignal);
  document.addEventListener("visibilitychange", refreshOnSignal);
  await refresh();
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
  const [creatorClaimable, setCreatorClaimable] = useState<bigint | null>(null);
  const [refundClaimable, setRefundClaimable] = useState<bigint | null>(null);
  const [creatorClaimState, setCreatorClaimState] = useState<TransactionState>(
    createTransactionState("disconnected"),
  );
  const [refundClaimState, setRefundClaimState] = useState<TransactionState>(
    createTransactionState("disconnected"),
  );
  const [claimBusy, setClaimBusy] = useState(false);
  const intentRef = useRef<import("@/transactions").ExactWrite | null>(null);
  const executionLockRef = useRef(false);
  const claimLockRef = useRef(false);
  const configuration = publicConfiguration();
  const curveExplorer = addressExplorerUrl(configuration, safeCurveAddress);
  const readiness = useWalletReadiness();
  const account = useAccount();
  const chainId = readiness.chainId;
  const publicClient = usePublicClient();
  const { data: walletClient } = useWalletClient();
  const reviewedRouter = reviewedRouterAddress(configuration.deployment!, configuration.chainId);
  const reviewedWeth = safeAddress(configuration.deployment?.weth);
  const graduated = token.phase.toLowerCase() === "graduated";
  const decimals = 18;
  const inputUnits = useMemo(() => {
    try {
      return input.trim() ? parseDecimal(input, decimals) : null;
    } catch {
      return null;
    }
  }, [input]);
  const slippageBps = useMemo(() => {
    return parseSlippageBps(slippage);
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
          if (parseQuoteQuantity(result.input, "quote input") !== inputUnits)
            throw new Error("QuoteChanged");
          const output = parseQuoteQuantity(result.output, "quote output");
          parseQuoteQuantity(result.refund, "quote refund");
          parseQuoteQuantity(result.next_virtual_eth, "next virtual ETH");
          parseQuoteQuantity(result.next_virtual_token, "next virtual token");
          parseQuoteQuantity(result.reserve_source_block.toString(), "quote source block");
          setQuote({
            output,
            fee:
              parseQuoteQuantity(result.protocol_fee, "protocol fee") +
              parseQuoteQuantity(result.creator_fee, "creator fee"),
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

  useEffect(() => {
    let cancelled = false;
    if (!publicClient || !account.address || !curveAddress) return;
    void Promise.all([
      publicClient.readContract({
        address: safeCurveAddress,
        abi: browserAbis.curve,
        functionName: "creator",
      }),
      publicClient.readContract({
        address: safeCurveAddress,
        abi: browserAbis.curve,
        functionName: "unclaimedCreatorFees",
      }),
      publicClient.readContract({
        address: safeCurveAddress,
        abi: browserAbis.curve,
        functionName: "pendingRefund",
        args: [account.address],
      }),
    ])
      .then(([creator, creatorFees, refund]) => {
        if (cancelled) return;
        setCreatorClaimable(
          String(creator).toLowerCase() === account.address!.toLowerCase()
            ? (creatorFees as bigint)
            : 0n,
        );
        setRefundClaimable(refund as bigint);
      })
      .catch(() => {
        if (!cancelled) {
          setCreatorClaimable(null);
          setRefundClaimable(null);
        }
      });
    return () => {
      cancelled = true;
    };
  }, [account.address, curveAddress, publicClient, safeCurveAddress]);

  const activeQuote = inputUnits && inputUnits > 0n ? quote : null;
  const minimum =
    activeQuote && slippageBps !== null ? minimumOutput(activeQuote.output, slippageBps) : null;
  const switchNetwork = () => void readiness.switchNetwork();
  const execute = async () => {
    if (graduated) return;
    if (executionLockRef.current) return;
    const resumingApproval = side === "sell" && approvalHash !== undefined;
    if (
      !resumingApproval &&
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
      minimum === null ||
      !inputUnits ||
      slippageBps === null ||
      chainId !== configuration.chainId ||
      !readiness.selectedAccountVerified
    ) {
      setState({ status: chainId !== configuration.chainId ? "wrong-chain" : "disconnected" });
      return;
    }
    setConfirming(false);
    executionLockRef.current = true;
    const accountAddress = account.address;
    const now = currentUnixSeconds();
    const deadline = transactionDeadline(now, DEFAULT_TTL);
    let submittedHash: Address | undefined;
    let failurePhase: "preflight" | "simulation" | "write" | "receipt" = "preflight";
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
      if (side === "buy") {
        const nativeBalance = await publicClient.getBalance({ address: accountAddress });
        if (nativeBalance < inputUnits) throw new Error("InsufficientETHBalance");
      }
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
          ? parseRuntimeQuantity((contractQuote as readonly unknown[])[1], "contract output")
          : parseRuntimeQuantity((contractQuote as readonly unknown[])[0], "contract output");
      const contractFee =
        parseRuntimeQuantity((contractQuote as readonly unknown[])[2], "protocol fee") +
        parseRuntimeQuantity((contractQuote as readonly unknown[])[3], "creator fee");
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
      setQuote({ output: contractOutput, fee: contractFee, source: "contract" });
      if (side === "sell") {
        const allowance = await publicClient.readContract({
          address: safeTokenAddress,
          abi: browserAbis.token,
          functionName: "allowance",
          args: [accountAddress, safeCurveAddress],
        });
        if (allowance < inputUnits) {
          const [approvalAccounts, approvalChainId] = await Promise.all([
            walletClient.getAddresses(),
            publicClient.getChainId(),
          ]);
          if (
            approvalChainId !== configuration.chainId ||
            approvalAccounts[0]?.toLowerCase() !== accountAddress.toLowerCase()
          )
            throw new Error("Wallet or network changed; review the approval again.");
          failurePhase = "simulation";
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
          failurePhase = "write";
          const hash = await walletClient.writeContract({
            address: safeTokenAddress,
            abi: browserAbis.token,
            functionName: "approve",
            account: accountAddress,
            args: approvalArgs,
          } as never);
          submittedHash = hash as Address;
          setApprovalHash(hash as Address);
          setState({ status: "submitted", hash: hash as Address });
          failurePhase = "receipt";
          const approvalReceipt = await publicClient.waitForTransactionReceipt({ hash });
          if (approvalReceipt.status !== "success") throw new Error("ReceiptReverted");
          setState({ status: "mined", hash: hash as Address });
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
      // Final account, chain, phase, and quote reads precede the exact simulation used for signing.
      const phaseBeforeSign = await publicClient.readContract({
        address: safeCurveAddress,
        abi: browserAbis.curve,
        functionName: "phase",
      });
      if (Number(phaseBeforeSign) !== 0) throw new Error("WrongPhase");
      const latestQuote =
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
      const latestOutput =
        side === "buy"
          ? parseRuntimeQuantity((latestQuote as readonly unknown[])[1], "contract output")
          : parseRuntimeQuantity((latestQuote as readonly unknown[])[0], "contract output");
      const latestMinimum = minimumOutput(latestOutput, slippageBps);
      const [walletAccounts, latestChainId] = await Promise.all([
        walletClient.getAddresses(),
        publicClient.getChainId(),
      ]);
      if (
        latestChainId !== configuration.chainId ||
        walletAccounts[0]?.toLowerCase() !== accountAddress.toLowerCase() ||
        !readiness.selectedAccountVerified
      )
        throw new Error("Wallet or network changed; review the transaction again.");
      const latestArgs =
        side === "buy"
          ? ([accountAddress, accountAddress, latestMinimum, deadline] as const)
          : ([inputUnits, accountAddress, latestMinimum, deadline] as const);
      const latestIntent = {
        account: accountAddress,
        target,
        value,
        args: latestArgs,
        deadline,
        minimumOutput: latestMinimum,
      };
      if (!sameWriteIntent(intent, latestIntent)) throw new Error("QuoteChanged");
      failurePhase = "simulation";
      await publicClient.simulateContract({
        address: target,
        abi: browserAbis.curve,
        functionName: side,
        account: accountAddress,
        args: latestArgs,
        value,
      } as never);
      setState(
        transitionTransaction(
          createTransactionState("simulating"),
          { type: "await-signature" },
          readiness.transactionReadiness,
        ),
      );
      failurePhase = "write";
      const hash = await walletClient.writeContract({
        address: target,
        abi: browserAbis.curve,
        functionName: side,
        account: accountAddress,
        args: latestArgs,
        value,
      } as never);
      submittedHash = hash as Address;
      setState({ status: "submitted", hash: hash as Address });
      failurePhase = "receipt";
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      if (receipt.status !== "success") throw new Error("ReceiptReverted");
      setState({ status: "mined", hash: hash as Address });
      setState({ status: "indexing", hash: hash as Address });
      void observeFreshSnapshot(
        configuration.apiBaseUrl,
        token.address,
        "trade",
        { status: "indexing", hash: hash as Address },
        setState,
      );
    } catch (error) {
      const message = classifyTransactionFailure(error, failurePhase);
      setState({
        status: message,
        hash: submittedHash ?? state.hash,
        error: decodeTransactionError(error).message,
      });
    } finally {
      executionLockRef.current = false;
    }
  };
  const executeClaim = async (kind: "creator" | "refund") => {
    if (
      claimLockRef.current ||
      !publicClient ||
      !walletClient ||
      !account.address ||
      chainId !== configuration.chainId ||
      !readiness.selectedAccountVerified
    )
      return;
    claimLockRef.current = true;
    setClaimBusy(true);
    const setClaimState = kind === "creator" ? setCreatorClaimState : setRefundClaimState;
    let submittedHash: Address | undefined;
    let failurePhase: "preflight" | "simulation" | "write" | "receipt" = "preflight";
    try {
      setClaimState({ status: "validating" });
      const [walletAccounts, latestChainId] = await Promise.all([
        walletClient.getAddresses(),
        publicClient.getChainId(),
      ]);
      if (
        latestChainId !== configuration.chainId ||
        walletAccounts[0]?.toLowerCase() !== account.address.toLowerCase()
      )
        throw new Error("Wallet or network changed; review the claim again.");
      if (kind === "creator") {
        const [creator, amount] = await Promise.all([
          publicClient.readContract({
            address: safeCurveAddress,
            abi: browserAbis.curve,
            functionName: "creator",
          }),
          publicClient.readContract({
            address: safeCurveAddress,
            abi: browserAbis.curve,
            functionName: "unclaimedCreatorFees",
          }),
        ]);
        if (
          String(creator).toLowerCase() !== account.address.toLowerCase() ||
          (amount as bigint) === 0n
        )
          throw new Error("NothingToClaim");
      } else {
        const amount = await publicClient.readContract({
          address: safeCurveAddress,
          abi: browserAbis.curve,
          functionName: "pendingRefund",
          args: [account.address],
        });
        if ((amount as bigint) === 0n) throw new Error("NothingToClaim");
      }
      const functionName = kind === "creator" ? "claimCreatorFees" : "claimRefund";
      setClaimState({ status: "simulating" });
      failurePhase = "simulation";
      await publicClient.simulateContract({
        address: safeCurveAddress,
        abi: browserAbis.curve,
        functionName,
        account: account.address,
      } as never);
      setClaimState({ status: "awaiting-signature" });
      failurePhase = "write";
      const hash = await walletClient.writeContract({
        address: safeCurveAddress,
        abi: browserAbis.curve,
        functionName,
        account: account.address,
      } as never);
      submittedHash = hash as Address;
      setClaimState({ status: "submitted", hash: submittedHash });
      failurePhase = "receipt";
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      if (receipt.status !== "success") throw new Error("ReceiptReverted");
      setClaimState({ status: "indexing", hash: submittedHash });
      void observeFreshSnapshot(
        configuration.apiBaseUrl,
        token.address,
        kind === "creator" ? "claim" : "refund",
        { status: "indexing", hash: submittedHash },
        setClaimState,
      );
    } catch (cause) {
      setClaimState({
        status: classifyTransactionFailure(cause, failurePhase),
        hash: submittedHash,
        error: decodeTransactionError(cause).message,
      });
    } finally {
      claimLockRef.current = false;
      setClaimBusy(false);
    }
  };
  const canTrade = Boolean(
    inputUnits &&
    inputUnits > 0n &&
    minimum !== null &&
    readiness.selectedAccountVerified &&
    chainId === configuration.chainId,
  );
  const canSubmit = canTrade && confirming;
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
        {reviewedRouter && reviewedWeth ? (
          <GraduatedSwapPanel token={token} router={reviewedRouter} weth={reviewedWeth} />
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
            setApprovalHash(undefined);
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
            setApprovalHash(undefined);
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
              <strong className="mono">
                {minimum === null ? "—" : formatBaseUnits(minimum, 18, 6)}
              </strong>
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
        lose value. Contract{" "}
        {curveExplorer ? (
          <a href={curveExplorer} target="_blank" rel="noreferrer" className="mono">
            {token.curve}
          </a>
        ) : (
          <span className="mono">{token.curve}</span>
        )}
        .
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
            <dd className="mono">{minimum === null ? "—" : formatBaseUnits(minimum, 18, 6)}</dd>
            <dt>Fee</dt>
            <dd className="mono">{quote ? eth(quote.fee) : "—"}</dd>
            <dt>Slippage</dt>
            <dd className="mono">{slippageBps === null ? "Invalid" : `${slippage}%`}</dd>
            <dt>Deadline</dt>
            <dd className="mono">
              {transactionDeadline(currentUnixSeconds(), DEFAULT_TTL).toString()} (Unix seconds)
            </dd>
            <dt>Network</dt>
            <dd>{configuration.deployment?.name}</dd>
            <dt>Contract</dt>
            <dd className="mono">
              {curveExplorer ? (
                <a href={curveExplorer} target="_blank" rel="noreferrer">
                  {token.curve}
                </a>
              ) : (
                token.curve
              )}
            </dd>
            {side === "sell" ? (
              <>
                <dt>Approval spender</dt>
                <dd className="mono">
                  {curveExplorer ? (
                    <a href={curveExplorer} target="_blank" rel="noreferrer">
                      {token.curve}
                    </a>
                  ) : (
                    token.curve
                  )}{" "}
                  (exact sell amount only)
                </dd>
              </>
            ) : null}
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
          disabled={!canTrade}
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
          Claimable creator fees:{" "}
          {creatorClaimable === null ? "Unavailable" : eth(creatorClaimable)}
          <br />
          Claimable refund: {refundClaimable === null ? "Unavailable" : eth(refundClaimable)}
        </span>
        <div className="transaction-actions">
          <Button
            size="sm"
            disabled={creatorClaimable === null || creatorClaimable === 0n || claimBusy}
            loading={
              creatorClaimState.status === "simulating" ||
              creatorClaimState.status === "awaiting-signature"
            }
            onClick={() => void executeClaim("creator")}
          >
            Claim creator fees
          </Button>
          <Button
            size="sm"
            disabled={refundClaimable === null || refundClaimable === 0n || claimBusy}
            loading={
              refundClaimState.status === "simulating" ||
              refundClaimState.status === "awaiting-signature"
            }
            onClick={() => void executeClaim("refund")}
          >
            Claim refund
          </Button>
        </div>
      </div>
      {[creatorClaimState, refundClaimState].map((claim) =>
        claim.status !== "disconnected" ? (
          <div className="transaction-progress" role="status" key={claim.hash ?? claim.status}>
            <Badge
              tone={
                claim.status === "reverted" || claim.status === "rejected-signature"
                  ? "danger"
                  : "warning"
              }
            >
              {statusLabel(claim.status)}
            </Badge>
            {claim.hash ? <span className="mono">{claim.hash}</span> : null}
            {claim.error ? <ErrorCopy error={new Error(claim.error)} /> : null}
          </div>
        ) : null,
      )}
    </section>
  );
}

function GraduatedSwapPanel({
  token,
  router,
  weth,
}: {
  token: { address: string; name: string; symbol: string };
  router: Address;
  weth: Address;
}) {
  const tokenAddress = safeAddress(token.address);
  const account = useAccount();
  const readiness = useWalletReadiness();
  const chainId = readiness.chainId;
  const publicClient = usePublicClient();
  const { data: walletClient } = useWalletClient();
  const configuration = publicConfiguration();
  const routerExplorer = addressExplorerUrl(configuration, router);
  const [side, setSide] = useState<"buy" | "sell">("buy");
  const [input, setInput] = useState("");
  const [slippage, setSlippage] = useState("5");
  const [output, setOutput] = useState<bigint | null>(null);
  const [confirming, setConfirming] = useState(false);
  const [state, setState] = useState<TransactionState>(createTransactionState("disconnected"));
  const [approvalHash, setApprovalHash] = useState<Address | undefined>();
  const lockRef = useRef(false);
  const inputUnits = useMemo(() => {
    try {
      return input.trim() ? parseDecimal(input) : null;
    } catch {
      return null;
    }
  }, [input]);
  const slippageBps = useMemo(() => {
    return parseSlippageBps(slippage);
  }, [slippage]);
  useEffect(() => {
    let cancelled = false;
    if (!tokenAddress || !inputUnits || inputUnits <= 0n || !publicClient) return;
    void publicClient
      .readContract({
        address: router,
        abi: browserAbis.router,
        functionName: "getAmountsOut",
        args: [inputUnits, side === "buy" ? [weth, tokenAddress] : [tokenAddress, weth]],
      } as never)
      .then((amounts) => {
        if (!cancelled)
          setOutput(
            parseQuoteQuantity(String((amounts as readonly unknown[]).at(-1)), "router output"),
          );
      })
      .catch(() => {
        if (!cancelled) setOutput(null);
      });
    return () => {
      cancelled = true;
    };
  }, [inputUnits, publicClient, router, side, tokenAddress, weth]);
  const minimum =
    output !== null && slippageBps !== null ? minimumOutput(output, slippageBps) : null;
  const execute = async () => {
    if (
      lockRef.current ||
      !tokenAddress ||
      !publicClient ||
      !walletClient ||
      !account.address ||
      inputUnits === null ||
      minimum === null ||
      chainId !== configuration.chainId ||
      !readiness.selectedAccountVerified
    )
      return;
    setConfirming(false);
    lockRef.current = true;
    let submittedHash: Address | undefined;
    let failurePhase: "preflight" | "simulation" | "write" | "receipt" = "preflight";
    try {
      const deadline = transactionDeadline(currentUnixSeconds(), DEFAULT_TTL);
      const path =
        side === "buy" ? ([weth, tokenAddress] as const) : ([tokenAddress, weth] as const);
      if (side === "buy") {
        const balance = await publicClient.getBalance({ address: account.address });
        if (balance < inputUnits) throw new Error("InsufficientETHBalance");
      }
      if (side === "sell") {
        const balance = await publicClient.readContract({
          address: tokenAddress,
          abi: browserAbis.token,
          functionName: "balanceOf",
          args: [account.address],
        });
        if (balance < inputUnits) throw new Error("ERC20InsufficientBalance");
        const allowance = await publicClient.readContract({
          address: tokenAddress,
          abi: browserAbis.token,
          functionName: "allowance",
          args: [account.address, router],
        });
        if (allowance < inputUnits) {
          const [approvalAccounts, approvalChainId] = await Promise.all([
            walletClient.getAddresses(),
            publicClient.getChainId(),
          ]);
          if (
            approvalChainId !== configuration.chainId ||
            approvalAccounts[0]?.toLowerCase() !== account.address.toLowerCase()
          )
            throw new Error("Wallet or network changed; review the approval again.");
          const approvalArgs = [router, inputUnits] as const;
          failurePhase = "simulation";
          await publicClient.simulateContract({
            address: tokenAddress,
            abi: browserAbis.token,
            functionName: "approve",
            account: account.address,
            args: approvalArgs,
          } as never);
          failurePhase = "write";
          const approvalTxHash = await walletClient.writeContract({
            address: tokenAddress,
            abi: browserAbis.token,
            functionName: "approve",
            account: account.address,
            args: approvalArgs,
          } as never);
          submittedHash = approvalTxHash as Address;
          setApprovalHash(approvalTxHash as Address);
          setState({ status: "submitted", hash: submittedHash });
          failurePhase = "receipt";
          const approvalReceipt = await publicClient.waitForTransactionReceipt({
            hash: approvalTxHash,
          });
          if (approvalReceipt.status !== "success") throw new Error("ReceiptReverted");
          setState({ status: "mined", hash: submittedHash });
          return;
        }
      }
      const initialArgs =
        side === "buy"
          ? ([minimum, path, account.address, deadline] as const)
          : ([inputUnits, minimum, path, account.address, deadline] as const);
      const value = side === "buy" ? inputUnits : 0n;
      const initialIntent = {
        account: account.address,
        target: router,
        value,
        args: initialArgs,
        deadline,
        minimumOutput: minimum,
      };
      const freshAmounts = await publicClient.readContract({
        address: router,
        abi: browserAbis.router,
        functionName: "getAmountsOut",
        args: [inputUnits, path],
      } as never);
      const freshOutput = parseQuoteQuantity(
        String((freshAmounts as readonly unknown[]).at(-1)),
        "router output",
      );
      const freshMinimum = minimumOutput(freshOutput, slippageBps!);
      const [walletAccounts, latestChainId] = await Promise.all([
        walletClient.getAddresses(),
        publicClient.getChainId(),
      ]);
      if (
        latestChainId !== configuration.chainId ||
        walletAccounts[0]?.toLowerCase() !== account.address.toLowerCase() ||
        !readiness.selectedAccountVerified
      )
        throw new Error("Wallet or network changed; review the transaction again.");
      const args =
        side === "buy"
          ? ([freshMinimum, path, account.address, deadline] as const)
          : ([inputUnits, freshMinimum, path, account.address, deadline] as const);
      const finalIntent = {
        account: account.address,
        target: router,
        value,
        args,
        deadline,
        minimumOutput: freshMinimum,
      };
      if (!sameWriteIntent(initialIntent, finalIntent)) throw new Error("QuoteChanged");
      failurePhase = "simulation";
      await publicClient.simulateContract({
        address: router,
        abi: browserAbis.router,
        functionName: side === "buy" ? "swapExactETHForTokens" : "swapExactTokensForETH",
        account: account.address,
        args,
        value,
      } as never);
      failurePhase = "write";
      const hash = await walletClient.writeContract({
        address: router,
        abi: browserAbis.router,
        functionName: side === "buy" ? "swapExactETHForTokens" : "swapExactTokensForETH",
        account: account.address,
        args,
        value,
      } as never);
      submittedHash = hash as Address;
      setState({ status: "submitted", hash: submittedHash });
      failurePhase = "receipt";
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      if (receipt.status !== "success") throw new Error("ReceiptReverted");
      const indexing = { status: "indexing" as const, hash: submittedHash };
      setState(indexing);
      void observeFreshSnapshot(
        configuration.apiBaseUrl,
        token.address,
        "trade",
        indexing,
        setState,
      );
    } catch (cause) {
      setState({
        status: classifyTransactionFailure(cause, failurePhase),
        hash: submittedHash,
        error: decodeTransactionError(cause).message,
      });
    } finally {
      lockRef.current = false;
    }
  };
  if (!tokenAddress)
    return (
      <UnavailableState
        title="Router unavailable"
        description="The token address is invalid for the reviewed router."
      />
    );
  const ready = Boolean(
    inputUnits &&
    inputUnits > 0n &&
    minimum !== null &&
    readiness.selectedAccountVerified &&
    chainId === configuration.chainId,
  );
  return (
    <div className="graduated-swap">
      {chainId !== configuration.chainId ? (
        <div className="transaction-warning" role="alert">
          Wrong network. Switch to {configuration.deployment?.name} before signing.
          <Button size="sm" onClick={() => void readiness.switchNetwork()}>
            Switch network
          </Button>
        </div>
      ) : null}
      <p className="transaction-risk">
        Reviewed router only:{" "}
        {routerExplorer ? (
          <a href={routerExplorer} target="_blank" rel="noreferrer" className="mono">
            {router}
          </a>
        ) : (
          <span className="mono">{router}</span>
        )}
        . Approval, if needed, is limited to this router and this sell amount.
      </p>
      <div className="trade-tabs" role="tablist" aria-label="Graduated trade side">
        <button
          type="button"
          role="tab"
          aria-selected={side === "buy"}
          className={side === "buy" ? "is-active" : ""}
          onClick={() => {
            setSide("buy");
            setApprovalHash(undefined);
            setInput("");
            setOutput(null);
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
            setApprovalHash(undefined);
            setInput("");
            setOutput(null);
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
        />
        <Input
          label="Slippage tolerance (%)"
          value={slippage}
          onChange={(event) => setSlippage(event.target.value)}
          inputMode="decimal"
        />
        {output !== null ? (
          <div className="quote-summary">
            <span>
              Router output <strong className="mono">{formatBaseUnits(output, 18, 6)}</strong>
            </span>
            <span>
              Minimum output{" "}
              <strong className="mono">
                {minimum === null ? "—" : formatBaseUnits(minimum, 18, 6)}
              </strong>
            </span>
          </div>
        ) : null}
      </div>
      {confirming ? (
        <div className="transaction-confirmation">
          <h3>Confirm {side}</h3>
          <dl>
            <dt>Network</dt>
            <dd>{configuration.deployment?.name}</dd>
            <dt>Contract</dt>
            <dd className="mono">
              {routerExplorer ? (
                <a href={routerExplorer} target="_blank" rel="noreferrer">
                  {router}
                </a>
              ) : (
                router
              )}
            </dd>
            <dt>Input / minimum</dt>
            <dd className="mono">
              {input} / {minimum === null ? "—" : formatBaseUnits(minimum, 18, 6)}
            </dd>
            <dt>Slippage</dt>
            <dd className="mono">{slippageBps === null ? "Invalid" : `${slippage}%`}</dd>
            <dt>Fee</dt>
            <dd className="mono">
              0 ETH router fee (Uniswap V2 has no protocol fee). Pool price impact is reflected in
              the quoted output.
            </dd>
            <dt>Deadline</dt>
            <dd className="mono">
              {transactionDeadline(currentUnixSeconds(), DEFAULT_TTL).toString()} (Unix seconds)
            </dd>
            {side === "sell" ? (
              <>
                <dt>Approval spender</dt>
                <dd className="mono">
                  {routerExplorer ? (
                    <a href={routerExplorer} target="_blank" rel="noreferrer">
                      {router}
                    </a>
                  ) : (
                    router
                  )}{" "}
                  (exact sell amount only)
                </dd>
              </>
            ) : null}
          </dl>
          <div className="transaction-actions">
            <Button variant="quiet" onClick={() => setConfirming(false)}>
              Back
            </Button>
            <Button variant="primary" disabled={!ready} onClick={() => void execute()}>
              Sign {side}
            </Button>
          </div>
        </div>
      ) : (
        <Button variant="primary" size="lg" disabled={!ready} onClick={() => setConfirming(true)}>
          {side === "sell" && approvalHash ? "Resume sell" : `Review ${side}`}
        </Button>
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
    </div>
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
  const { connect, connectors, isPending: connectPending } = useConnect();
  const launchChainId = readiness.chainId;
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
  const [defaultsRead, setDefaultsRead] = useState(false);
  const [launchesPaused, setLaunchesPaused] = useState<boolean | null>(null);
  const [tradingPaused, setTradingPaused] = useState<boolean | null>(null);
  const [engineEnabled, setEngineEnabled] = useState<boolean | null>(null);
  const executionLockRef = useRef(false);
  const deployment = configuration.deployment as ReviewedDeployment;
  const factoryExplorer = deployment.factory
    ? addressExplorerUrl(configuration, deployment.factory as Address)
    : null;
  const switchNetwork = () => void readiness.switchNetwork();
  useEffect(() => {
    if (!publicClient || !deployment.factory) return;
    void Promise.all([
      publicClient.readContract({
        address: deployment.factory as Address,
        abi: browserAbis.factory,
        functionName: "launchFee",
      }),
      publicClient.readContract({
        address: deployment.factory as Address,
        abi: browserAbis.factory,
        functionName: "futureDefaults",
      }),
      publicClient.readContract({
        address: deployment.factory as Address,
        abi: browserAbis.factory,
        functionName: "launchesPaused",
      }),
      publicClient.readContract({
        address: deployment.factory as Address,
        abi: browserAbis.factory,
        functionName: "tradingPaused",
      }),
      publicClient.readContract({
        address: deployment.factory as Address,
        abi: browserAbis.factory,
        functionName: "engineEnabled",
        args: [1],
      }),
    ])
      .then(([fee, , paused, trading, enabled]) => {
        setLaunchFee(fee as bigint);
        setDefaultsRead(true);
        setLaunchesPaused(Boolean(paused));
        setTradingPaused(Boolean(trading));
        setEngineEnabled(Boolean(enabled));
      })
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
    if (executionLockRef.current) return;
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
    setConfirming(false);
    executionLockRef.current = true;
    let submittedHash: Address | undefined;
    let failurePhase: "preflight" | "simulation" | "write" | "receipt" = "preflight";
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
      const [latestLaunchFee, latestLaunchesPaused, latestTradingPaused, latestEngineEnabled] =
        await Promise.all([
          publicClient.readContract({
            address: deployment.factory as Address,
            abi: browserAbis.factory,
            functionName: "launchFee",
          }) as Promise<bigint>,
          publicClient.readContract({
            address: deployment.factory as Address,
            abi: browserAbis.factory,
            functionName: "launchesPaused",
          }) as Promise<boolean>,
          publicClient.readContract({
            address: deployment.factory as Address,
            abi: browserAbis.factory,
            functionName: "tradingPaused",
          }) as Promise<boolean>,
          publicClient.readContract({
            address: deployment.factory as Address,
            abi: browserAbis.factory,
            functionName: "engineEnabled",
            args: [1],
          }) as Promise<boolean>,
        ]);
      if (!latestEngineEnabled) throw new Error("EngineDisabled");
      if (latestLaunchesPaused) throw new Error("LaunchesPaused");
      if (buyUnits! > 0n && latestTradingPaused) throw new Error("TradingPaused");
      const exactValue = calculateLaunchValue(latestLaunchFee, buyUnits!);
      const nativeBalance = await publicClient.getBalance({ address: account.address });
      if (nativeBalance < exactValue) throw new Error("InsufficientETHBalance");
      if (latestLaunchFee !== launchFee || exactValue !== value)
        throw new Error("LaunchValueMismatch");
      const capturedIntent = {
        account: account.address,
        target: deployment.factory,
        value: exactValue,
        args,
        deadline,
      };
      const [simulationAccounts, simulationChainId] = await Promise.all([
        walletClient.getAddresses(),
        publicClient.getChainId(),
      ]);
      if (
        simulationChainId !== configuration.chainId ||
        simulationAccounts[0]?.toLowerCase() !== account.address.toLowerCase()
      )
        throw new Error("Wallet or network changed; review the launch again.");
      failurePhase = "simulation";
      await publicClient.simulateContract({
        address: deployment.factory as Address,
        abi: browserAbis.factory,
        functionName: "launch",
        account: account.address,
        args,
        value: exactValue,
      } as never);
      const [beforeSignLaunchesPaused, beforeSignEngineEnabled] = await Promise.all([
        publicClient.readContract({
          address: deployment.factory as Address,
          abi: browserAbis.factory,
          functionName: "launchesPaused",
        }) as Promise<boolean>,
        publicClient.readContract({
          address: deployment.factory as Address,
          abi: browserAbis.factory,
          functionName: "engineEnabled",
          args: [1],
        }) as Promise<boolean>,
      ]);
      if (beforeSignLaunchesPaused) throw new Error("LaunchesPaused");
      if (!beforeSignEngineEnabled) throw new Error("EngineDisabled");
      const [writeAccounts, writeChainId] = await Promise.all([
        walletClient.getAddresses(),
        publicClient.getChainId(),
      ]);
      if (
        writeChainId !== configuration.chainId ||
        writeAccounts[0]?.toLowerCase() !== account.address.toLowerCase()
      )
        throw new Error("Wallet or network changed; review the launch again.");
      const writeIntent = {
        account: account.address,
        target: deployment.factory,
        value: exactValue,
        args,
        deadline,
      };
      if (!sameWriteIntent(capturedIntent, writeIntent))
        throw new Error("Write intent changed; retry safely.");
      setState({ status: "awaiting-signature" });
      failurePhase = "write";
      const hash = await walletClient.writeContract({
        address: deployment.factory as Address,
        abi: browserAbis.factory,
        functionName: "launch",
        account: account.address,
        args,
        value: exactValue,
      } as never);
      submittedHash = hash as Address;
      setState({ status: "submitted", hash: hash as Address });
      failurePhase = "receipt";
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      if (receipt.status !== "success") throw new Error("ReceiptReverted");
      setState({ status: "indexing", hash: hash as Address });
      const launched = parseEventLogs({
        abi: browserAbis.factory,
        eventName: "TokenLaunched",
        logs: receipt.logs,
        strict: false,
      }).find((event) => typeof event.args.token === "string");
      if (launched && typeof launched.args.token === "string")
        void observeFreshSnapshot(
          configuration.apiBaseUrl,
          launched.args.token,
          "launch",
          { status: "indexing", hash: hash as Address },
          setState,
        );
    } catch (cause) {
      setState({
        status: classifyTransactionFailure(cause, failurePhase),
        hash: submittedHash,
        error: decodeTransactionError(cause).message,
      });
    } finally {
      executionLockRef.current = false;
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
          {!readiness.address ? (
            <div className="transaction-warning" role="status">
              Connect the selected wallet before reviewing this launch.
              <Button
                size="sm"
                loading={connectPending}
                disabled={connectors.length === 0}
                onClick={() => {
                  const connector = connectors[0];
                  if (connector) connect({ connector });
                }}
              >
                Connect wallet
              </Button>
            </div>
          ) : null}
          {launchChainId !== configuration.chainId ? (
            <div className="transaction-warning" role="alert">
              Wrong network. Switch to {deployment.name} before signing.
              <Button size="sm" onClick={switchNetwork}>
                Switch network
              </Button>
            </div>
          ) : null}
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
              Factory defaults{" "}
              <strong className="mono">{defaultsRead ? "Read from chain" : "Unavailable"}</strong>
            </span>
            <span>
              Launches paused{" "}
              <strong className="mono">
                {launchesPaused === null ? "Unavailable" : launchesPaused ? "Yes" : "No"}
              </strong>
            </span>
            <span>
              Trading paused{" "}
              <strong className="mono">
                {tradingPaused === null ? "Unavailable" : tradingPaused ? "Yes" : "No"}
              </strong>
            </span>
            <span>
              Engine v1 enabled{" "}
              <strong className="mono">
                {engineEnabled === null ? "Unavailable" : engineEnabled ? "Yes" : "No"}
              </strong>
            </span>
            <small>
              Engine v1 is the only generated launch ABI. Pause state is read from the reviewed
              factory immediately before confirmation and simulation.
            </small>
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
                <dt>Fee</dt>
                <dd className="mono">{launchFee === null ? "Unavailable" : eth(launchFee)}</dd>
                <dt>Developer buy / minimum output</dt>
                <dd className="mono">{buy || "0"} ETH / 0 tokens</dd>
                <dt>Network</dt>
                <dd>{deployment.name}</dd>
                <dt>Contract</dt>
                <dd className="mono">
                  {factoryExplorer ? (
                    <a href={factoryExplorer} target="_blank" rel="noreferrer">
                      {deployment.factory}
                    </a>
                  ) : (
                    deployment.factory
                  )}
                </dd>
                <dt>Deadline</dt>
                <dd className="mono">
                  {transactionDeadline(currentUnixSeconds(), DEFAULT_TTL).toString()} (Unix seconds)
                </dd>
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
                !defaultsRead ||
                launchesPaused !== false ||
                engineEnabled !== true ||
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
