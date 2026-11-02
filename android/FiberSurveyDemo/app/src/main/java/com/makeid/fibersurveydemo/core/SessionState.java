package com.makeid.fibersurveydemo.core;

/** Main-thread session and transaction identifiers; no saved/automatic device actions. */
public final class SessionState {
    public enum Phase { IDLE, SCANNING, FINDING, CONNECTING, SERVICE_DISCOVERED, READY, COMMAND_PENDING, DISCONNECTED, RESULT_UNKNOWN, CLOSING }
    private long session;
    private long sequence;
    private long command;
    public long next() { command=0; return ++session; }
    public long session() { return session; }
    public boolean isCurrent(long value) { return value==session; }
    public long beginCommand() {
        if (command!=0) throw new IllegalStateException("关机命令正在等待结果");
        command=++sequence; return command;
    }
    public boolean pending() { return command!=0; }
    public boolean commandCurrent(long token) { return command!=0 && token==command; }
    public boolean finishCommand(long token) {
        if (!commandCurrent(token)) return false;
        command=0; return true;
    }
}
