export interface ActiveCycle {
    employer: string;
    cycleId:  bigint;
}

export interface AgentState {
    lastScannedBlock: number;
    knownEmployers:   string[];
}

export interface RebalanceResult {
    employer:   string;
    cycleId:    bigint;
    success:    boolean;
    actionType: string;
    txHash?:    string;
    error?:     string;
    gasUsed?:   bigint;
}

export interface CycleStartedEvent {
    employer: string;
    cycleId:  bigint;
    amount:   bigint;
    payday:   bigint;
}

export enum ActionType {
    CycleStarted     = 0,
    Rebalanced       = 1,
    BufferAdjusted   = 2,
    MovedToReserve   = 3,
    PoolBelowMinAPY  = 4,
    PaydayTriggered  = 5,
    NoActionNeeded   = 6
}

export const ACTION_TYPE_LABELS: Record<number, string> = {
    0: "CycleStarted",
    1: "Rebalanced",
    2: "BufferAdjusted",
    3: "MovedToReserve",
    4: "PoolBelowMinAPY",
    5: "PaydayTriggered",
    6: "NoActionNeeded"
};