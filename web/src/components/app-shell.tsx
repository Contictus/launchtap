"use client";

import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import {
  ArrowSquareOut,
  BookOpenText,
  ChartLineUp,
  Compass,
  List,
  Moon,
  Plus,
  ShieldCheck,
  Sun,
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
  const [theme, setTheme] = useState<"dark" | "light">("dark");
  const configuration = publicConfiguration();
  const deploymentReady = configuration.status === "ready";
  useEffect(() => {
    const saved = window.localStorage.getItem("launchpad-theme");
    const next = saved === "light" ? "light" : "dark";
    document.documentElement.dataset.theme = next;
    if (next === "dark") return;
    const sync = window.setTimeout(() => setTheme(next), 0);
    return () => window.clearTimeout(sync);
  }, []);
  function toggleTheme() {
    const next = theme === "dark" ? "light" : "dark";
    setTheme(next);
    document.documentElement.dataset.theme = next;
    window.localStorage.setItem("launchpad-theme", next);
  }
  const active = (href: string) => (href === "/" ? pathname === "/" : pathname.startsWith(href));
  return (
    <div className="app-frame">
      <header className="app-navbar" aria-label="Primary navigation">
        <nav className="navbar-links" aria-label="Desktop primary navigation">
          {navItems.map(({ href, label, icon: Icon, primary }) => (
            <a
              key={href}
              href={href}
              className={`navbar-link ${active(href) ? "is-active" : ""} ${primary ? "is-primary" : ""}`}
              aria-current={active(href) ? "page" : undefined}
            >
              <Icon size={18} weight={active(href) ? "fill" : "regular"} aria-hidden="true" />
              <span>{label}</span>
            </a>
          ))}
        </nav>
        <div className="navbar-actions">
          <span className="navbar-network">
            <span
              className={`state-dot ${deploymentReady ? "state-dot-success" : "state-dot-warning"}`}
            />
            {deploymentReady ? "Testnet ready" : "Read-only mode"}
          </span>
          <button
            type="button"
            className="theme-toggle"
            onClick={toggleTheme}
            aria-label={`Switch to ${theme === "dark" ? "light" : "dark"} theme`}
            title={`Switch to ${theme === "dark" ? "light" : "dark"} theme`}
          >
            {theme === "dark" ? <Sun size={16} /> : <Moon size={16} />}
          </button>
          <Button
            variant="quiet"
            size="sm"
            onClick={() => setMenuOpen(true)}
            className="navbar-wallet"
          >
            <Wallet size={15} /> <span>Connect wallet</span>
          </Button>
          <button
            className="ui-icon-button navbar-menu-button"
            onClick={() => setMenuOpen(true)}
            aria-label="Open navigation"
          >
            <List size={22} />
          </button>
        </div>
      </header>
      <main className="app-content">
        {children}
        <footer className="app-footer">
          <div>
            <span className="footer-mark" aria-label="Protocol mark">◈</span>
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
