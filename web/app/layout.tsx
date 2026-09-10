import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Launchpad",
  description: "Non-custodial token launchpad diagnostics",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
