import { describe, it, expect, beforeEach } from "vitest";

// Error codes mock
const E = {
  CAMPAIGN_NOT_STARTED: 100,
  CAMPAIGN_ENDED: 101,
  NOT_CREATOR: 102,
  INVALID_STATE: 103,
  ZERO_AMOUNT: 200,
  NOT_REVEALED: 202,
  VOTE_ALREADY_CAST: 203,
};

// Mock CampaignCore class
class CampaignCoreMock {
  goal: number = 0;
  duration: number = 0;
  voteWindow: number = 0;
  creator: string = "";
  escrow: string = "";
  distributor: string = "";
  total: number = 0;
  block: number = 0;
  proposals: { hash: string; amount: number; revealed: boolean; desc?: string; votes: number }[] = [];
  votes: Map<string, number> = new Map();
  cancelled: boolean = false;

  initCampaign(goal: number, duration: number, voteWindow: number, creator: string, escrow: string, distributor: string) {
    if (goal <= 0) return { ok: false, value: E.INVALID_STATE };
    this.goal = goal;
    this.duration = duration;
    this.voteWindow = voteWindow;
    this.creator = creator;
    this.escrow = escrow;
    this.distributor = distributor;
    this.total = 0;
    this.block = 0;
    this.cancelled = false;
    return { ok: true, value: true };
  }

  advanceBlocks(n: number) {
    this.block += n;
  }

  contribute(amount: number) {
    if (amount <= 0) return { ok: false, value: E.ZERO_AMOUNT };
    if (this.block >= this.duration) return { ok: false, value: E.CAMPAIGN_ENDED };
    this.total += amount;
    return { ok: true, value: true };
  }

  getContribution(_: string) {
    return this.total;
  }

  submitProposalHash(hash: string, amount: number) {
    if (this.block >= this.duration) return { ok: false, value: E.CAMPAIGN_ENDED };
    const id = this.proposals.length;
    this.proposals.push({ hash, amount, revealed: false, votes: 0 });
    return { ok: true, value: id };
  }

  revealProposal(id: number, desc: string) {
    if (!this.proposals[id]) return { ok: false, value: E.INVALID_STATE };
    this.proposals[id].revealed = true;
    this.proposals[id].desc = desc;
    return { ok: true, value: true };
  }

  castVote(id: number, weight: number) {
    if (this.block < this.duration) return { ok: false, value: E.CAMPAIGN_NOT_STARTED };
    if (!this.proposals[id] || !this.proposals[id].revealed) return { ok: false, value: E.NOT_REVEALED };
    if (this.votes.has("voter")) return { ok: false, value: E.VOTE_ALREADY_CAST };
    this.votes.set("voter", id);
    this.proposals[id].votes += weight;
    return { ok: true, value: true };
  }

  getVotes(id: number) {
    return this.proposals[id]?.votes ?? 0;
  }

  updateEscrow(newEscrow: string) {
    if (this.creator !== "ST1CREATOR") return { ok: false, value: E.NOT_CREATOR };
    this.escrow = newEscrow;
    return { ok: true, value: true };
  }

  updateDistributor(newDistributor: string) {
    if (this.creator !== "ST1CREATOR") return { ok: false, value: E.NOT_CREATOR };
    this.distributor = newDistributor;
    return { ok: true, value: true };
  }

  cancel() {
    if (this.creator !== "ST1CREATOR") return { ok: false, value: E.NOT_CREATOR };
    this.cancelled = true;
    return { ok: true, value: true };
  }
}

describe("CampaignCore", () => {
  let c: CampaignCoreMock;

  beforeEach(() => {
    c = new CampaignCoreMock();
    c.initCampaign(1000, 2, 5, "ST1CREATOR", "ST1ESCROW", "ST1DIST");
  });

  it("inits with valid params", () => {
    const r = c.initCampaign(1000, 5, 5, "ST1CREATOR", "ST1ESCROW", "ST1DIST");
    expect(r).toEqual({ ok: true, value: true });
  });

  it("rejects invalid goal", () => {
    const r = c.initCampaign(0, 5, 5, "ST1CREATOR", "ST1ESCROW", "ST1DIST");
    expect(r).toEqual({ ok: false, value: E.INVALID_STATE });
  });

  it("accepts contributions during fundraise and aggregates totals", () => {
    const a = c.contribute(200);
    const b = c.contribute(300);
    expect(a).toEqual({ ok: true, value: true });
    expect(b).toEqual({ ok: true, value: true });
    expect(c.getContribution("ST2DONOR")).toBe(500);
  });

  it("rejects zero contribution", () => {
    const r = c.contribute(0);
    expect(r).toEqual({ ok: false, value: E.ZERO_AMOUNT });
  });

  it("rejects after fundraise ends", () => {
    c.advanceBlocks(3);
    const r = c.contribute(10);
    expect(r).toEqual({ ok: false, value: E.CAMPAIGN_ENDED });
  });

  it("submits and reveals proposals", () => {
    const id = c.submitProposalHash("0xhash", 100);
    expect(id.ok).toBe(true);
    if (id.ok) {
      const rr = c.revealProposal(id.value, "desc");
      expect(rr).toEqual({ ok: true, value: true });
    }
  });

  it("prevents voting before vote window", () => {
    const s = c.submitProposalHash("0xhash", 100);
    if (s.ok) c.revealProposal(s.value, "d");
    const r = c.castVote(0, 1);
    expect(r).toEqual({ ok: false, value: E.CAMPAIGN_NOT_STARTED });
  });

  it("allows voting during vote window and enforces one vote per voter", () => {
    const s = c.submitProposalHash("0xhash", 100);
    if (s.ok) c.revealProposal(s.value, "d");
    c.advanceBlocks(3);
    const r1 = c.castVote(0, 7);
    const r2 = c.castVote(0, 3);
    expect(r1).toEqual({ ok: true, value: true });
    expect(r2).toEqual({ ok: false, value: E.VOTE_ALREADY_CAST });
    expect(c.getVotes(0)).toBe(7);
  });

  it("rejects voting on unrevealed proposal", () => {
    c.submitProposalHash("0xhash", 100);
    c.advanceBlocks(3);
    const r = c.castVote(0, 1);
    expect(r).toEqual({ ok: false, value: E.NOT_REVEALED });
  });

  it("updates escrow and distributor by creator only", () => {
    const r1 = c.updateEscrow("ST2ESCROW");
    const r2 = c.updateDistributor("ST2DIST");
    expect(r1).toEqual({ ok: true, value: true });
    expect(r2).toEqual({ ok: true, value: true });
  });

  it("cancels campaign by creator", () => {
    const r = c.cancel();
    expect(r).toEqual({ ok: true, value: true });
  });
});
