"use client";

import { usePathname } from "next/navigation";
import Link from "next/link";
import { useState } from "react";
import {
  ArrowSquareOut,
  BookOpenText,
  ChartLineUp,
  Compass,
  List,
  Plus,
  RocketLaunch,
  ShieldCheck,
  Trophy,
  UserCircle,
  Wallet,
} from "./icons";
import { Button, SafeExternalLink, Sheet } from "./primitives";
import { publicConfiguration } from "@/config/public";

const navItems = [
  { href: "/", label: "Explore", icon: Compass },
  { href: "/graduated", label: "Graduated", icon: Trophy },
  { href: "/create", label: "Create", icon: Plus, primary: true },
  { href: "/analytics", label: "Analytics", icon: ChartLineUp },
  { href: "/docs", label: "Docs", icon: BookOpenText },
  { href: "/profile", label: "Profile", icon: UserCircle },
];

export function AppShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const [menuOpen, setMenuOpen] = useState(false);
  const configuration = publicConfiguration();
  const deploymentReady = configuration.status === "ready";
  const active = (href: string) => (href === "/" ? pathname === "/" : pathname.startsWith(href));
  return (
    <div className="app-frame">
      <aside className="app-rail" aria-label="Desktop application rail">
        <Link href="/" className="brand-mark">
          <span className="brand-stamp" aria-hidden="true">
            LP
          </span>
          <span>
            <strong>Launchpad</strong>
            <small>Onchain launch desk</small>
          </span>
        </Link>
        <div className="rail-rule" />
        <nav className="rail-nav" aria-label="Desktop primary navigation">
          {navItems.map(({ href, label, icon: Icon, primary }) => (
            <a
              key={href}
              href={href}
              className={`rail-link ${active(href) ? "is-active" : ""} ${primary ? "is-primary" : ""}`}
              aria-current={active(href) ? "page" : undefined}
            >
              <Icon size={18} weight={active(href) ? "fill" : "regular"} aria-hidden="true" />
              <span>{label}</span>
              {primary ? <span className="rail-link-key">+</span> : null}
            </a>
          ))}
        </nav>
        <div className="rail-bottom">
          <div className="network-label">
            <span className="state-dot state-dot-warning" aria-hidden="true" />
            {deploymentReady ? configuration.deployment?.name : "Deployment unavailable"}
          </div>
          <p>
            {deploymentReady
              ? "Reviewed deployment connected. Contract reads and wallet actions remain user-controlled."
              : "Public configuration is not connected. The shell stays read-only until a reviewed deployment is available."}
          </p>
          <SafeExternalLink href="https://robinhoodchain.blockscout.com" className="rail-external">
            Open explorer <ArrowSquareOut size={13} />
          </SafeExternalLink>
        </div>
      </aside>
      <header className="mobile-topbar">
        <Link href="/" className="brand-mark">
          <span className="brand-stamp" aria-hidden="true">
            LP
          </span>
          <strong>Launchpad</strong>
        </Link>
        <button
          className="ui-icon-button"
          onClick={() => setMenuOpen(true)}
          aria-label="Open navigation"
        >
          <List size={22} />
        </button>
      </header>
      <main className="app-content">
        <div className="content-topline">
          <span className="route-label">
            <RocketLaunch size={15} aria-hidden="true" /> Launch route
          </span>
          <span className="route-line" aria-hidden="true" />
          <span className="route-state">Read-only shell</span>
          <Button
            variant="quiet"
            size="sm"
            onClick={() => setMenuOpen(true)}
            className="desktop-menu-button"
          >
            <Wallet size={15} /> Connect wallet
          </Button>
        </div>
        {children}
        <footer className="app-footer">
          <div>
            <strong>Launchpad</strong>
            <p>Non-custodial by design. You sign every transaction in your selected wallet.</p>
          </div>
          <div className="footer-links">
            <a href="/docs">Risk and finality</a>
            <SafeExternalLink href="https://robinhoodchain.blockscout.com">
              Explorer <ArrowSquareOut size={13} />
            </SafeExternalLink>
          </div>
        </footer>
      </main>
      <nav className="mobile-bottom-nav" aria-label="Mobile primary navigation">
        {navItems.slice(0, 4).map(({ href, label, icon: Icon }) => (
          <a
            key={href}
            href={href}
            className={active(href) ? "is-active" : ""}
            aria-current={active(href) ? "page" : undefined}
          >
            <Icon size={20} weight={active(href) ? "fill" : "regular"} aria-hidden="true" />
            <span>{label}</span>
          </a>
        ))}
      </nav>
      <Sheet open={menuOpen} title="Navigate" onClose={() => setMenuOpen(false)}>
        <nav className="sheet-nav" aria-label="Mobile menu navigation">
          {navItems.map(({ href, label, icon: Icon }) => (
            <a
              key={href}
              href={href}
              onClick={() => setMenuOpen(false)}
              className={active(href) ? "is-active" : ""}
            >
              <Icon size={20} />
              {label}
            </a>
          ))}
        </nav>
        <div className="sheet-note">
          <ShieldCheck size={18} />
          <p>
            Wallet connections and signing remain user-controlled. Launchpad never takes custody of
            funds.
          </p>
        </div>
      </Sheet>
    </div>
  );
}
