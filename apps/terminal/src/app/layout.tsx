import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Aether-War Command",
  description: "DeFAI Autonomous World — Tactical Terminal",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body style={{ margin: 0, background: "#0A0E14", color: "#e2e8f0", fontFamily: "system-ui, monospace" }}>
        {children}
      </body>
    </html>
  );
}
