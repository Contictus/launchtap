import { parseTokenAddress } from "@/token/address";
import { TokenDetail } from "@/token/token-detail";
import Link from "next/link";

export default async function TokenPage({ params }: { params: Promise<{ address: string }> }) {
  const { address } = await params;
  const parsed = parseTokenAddress(address);
  if (!parsed) return <TokenNotFound />;
  return <TokenDetail address={parsed} />;
}

function TokenNotFound() {
  return (
    <div className="page-stack token-page">
      <section className="ui-state ui-error-state" role="alert">
        <div>
          <p className="panel-kicker">Token route</p>
          <h1>Token not found</h1>
          <p>This address is not a valid EVM token address.</p>
          <Link className="ui-button ui-button-secondary ui-button-md" href="/">
            Return to Explore
          </Link>
        </div>
      </section>
    </div>
  );
}
