"use client";
import { useState, useEffect, useCallback } from "react";
import { Target, HardHat, Handshake, PiggyBank, Play, Zap, Activity, BarChart3, Cpu, Map } from "lucide-react";

interface AgentReport {
  agent: string; swarmId: number; tick: number; reasoning: string; action: string; confidence: number;
}

const AGENTS = [
  { key: "scout", name: "Scout", title: "The Oracle", icon: <Target className="w-4 h-4" />, color: "#06b6d4" },
  { key: "builder", name: "Builder", title: "The Infrastructure", icon: <HardHat className="w-4 h-4" />, color: "#10b981" },
  { key: "closer", name: "Closer", title: "The Negotiator", icon: <Handshake className="w-4 h-4" />, color: "#d4a853" },
  { key: "treasurer", name: "Treasurer", title: "The Risk Manager", icon: <PiggyBank className="w-4 h-4" />, color: "#f59e0b" },
];

export default function WarRoom() {
  const [tick, setTick] = useState(0);
  const [reports, setReports] = useState<AgentReport[]>([]);
  const [activeLog, setActiveLog] = useState<string[]>([]);
  const [running, setRunning] = useState(false);

  const runTick = useCallback(async () => {
    setRunning(true);
    try {
      const res = await fetch("/api/tick");
      const data = await res.json();
      if (data.tick) setTick(data.tick);
      if (data.reports) {
        setReports(data.reports);
        // Build live log from reports
        const lines = data.reports.map((r: AgentReport) => 
          `[${r.agent.toUpperCase()}] Swarm #${r.swarmId} — ${r.reasoning} (${r.confidence}%)`
        );
        setActiveLog(prev => [...lines, ...prev].slice(0, 50));
      }
    } catch {}
    setRunning(false);
  }, []);

  useEffect(() => {
    runTick();
    const interval = setInterval(runTick, 10000);
    return () => clearInterval(interval);
  }, [runTick]);

  return (
    <div className="min-h-screen p-4 md:p-6 space-y-4" style={{ background: "linear-gradient(180deg, #0A0E14 0%, #111827 100%)" }}>
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl flex items-center justify-center" style={{ background: "linear-gradient(135deg, #FFD70030, #FFD70010)", border: "1px solid rgba(255,215,0,0.2)" }}>
            <Cpu className="w-5 h-5" style={{ color: "#FFD700" }} />
          </div>
          <div>
            <h1 className="text-2xl font-bold text-white">Aether-War Command</h1>
            <p className="text-[11px] text-slate-400">Tick #{tick} · 10 Swarms Active · Sector Grid 10×10</p>
          </div>
        </div>
        <button onClick={runTick} disabled={running} className="px-4 py-2 rounded-xl text-xs font-bold text-[#0A0E14] flex items-center gap-2" style={{ background: "linear-gradient(135deg, #FFD700, #FFA500)" }}>
          <Play className="w-3.5 h-3.5" /> {running ? "Processing..." : "Process Tick"}
        </button>
      </div>

      {/* Agent Cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        {AGENTS.map(agent => {
          const report = reports.find(r => r.agent === agent.key);
          return (
            <div key={agent.key} className="p-4 rounded-2xl border border-white/[0.04]" style={{ background: "rgba(10,14,20,0.8)", backdropFilter: "blur(12px)" }}>
              <div className="flex items-center gap-2 mb-2">
                <div className="w-8 h-8 rounded-lg flex items-center justify-center" style={{ background: `${agent.color}15`, color: agent.color }}>{agent.icon}</div>
                <div>
                  <h3 className="text-xs font-bold text-white">{agent.name}</h3>
                  <p className="text-[9px] text-slate-500">{agent.title}</p>
                </div>
              </div>
              {report ? (
                <div className="space-y-1">
                  <p className="text-[10px] text-slate-300 leading-relaxed line-clamp-2">{report.reasoning}</p>
                  <div className="flex items-center justify-between">
                    <span className="text-[9px] px-1.5 py-0.5 rounded-full" style={{ background: `${agent.color}10`, color: agent.color }}>{report.action.replace(/_/g, " ")}</span>
                    <span className="text-[9px] text-slate-500">{report.confidence}%</span>
                  </div>
                </div>
              ) : (
                <p className="text-[10px] text-slate-600">Awaiting tick...</p>
              )}
            </div>
          );
        })}
      </div>

      {/* Live Telemetry */}
      <div className="rounded-2xl border border-white/[0.04] overflow-hidden" style={{ background: "rgba(10,14,20,0.9)" }}>
        <div className="px-4 py-3 border-b border-white/[0.04] flex items-center gap-2">
          <Activity className="w-3.5 h-3.5" style={{ color: "#FFD700" }} />
          <h3 className="text-xs font-bold text-white uppercase tracking-wider">Live Telemetry Stream</h3>
        </div>
        <div className="p-4 font-mono text-[11px] space-y-1.5 max-h-[400px] overflow-y-auto" style={{ background: "rgba(0,0,0,0.3)" }}>
          {activeLog.map((line, i) => (
            <div key={i} className="flex items-start gap-2">
              <span className="text-slate-700 shrink-0">{`[T+${tick - activeLog.length + i + 1}]`}</span>
              <span className="text-slate-300">{line}</span>
            </div>
          ))}
          {activeLog.length === 0 && <p className="text-slate-600">No telemetry yet — process a tick to begin.</p>}
        </div>
      </div>
    </div>
  );
}
