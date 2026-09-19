import Link from "next/link";
import { LaunchPanel } from "@/transactions-panel";

export default function CreatePage() {
  return (
    <div className="page-stack create-page">
      <div className="create-page-toolbar">
        <Link className="create-back-button" href="/">
          <span aria-hidden="true">‹</span> Back
        </Link>
        <div className="create-version-switch" aria-label="Launch version">
          <span className="is-active">v2</span>
          <span>v1</span>
        </div>
      </div>
      <LaunchPanel />
    </div>
  );
}
