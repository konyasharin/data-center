using DataCenter.Sim.Estate;
using DataCenter.Sim.Work;
using Godot;

namespace DataCenter;

/// <summary>
/// The scene's handle on the money and the job queue.
///
/// Same rule as <see cref="CablingBridge"/>: ints and strings across, no decisions of
/// its own. Buying is the one thing it composes — charging the ledger and queueing the
/// work are a pair, and a caller that could do one without the other would eventually
/// do exactly that.
/// </summary>
[GlobalClass]
public partial class EstateBridge : RefCounted
{
	private readonly Ledger _money = new(24000);
	private readonly JobQueue _jobs = new();

	public long Balance() => _money.Balance;
	public long Spent() => _money.Spent;

	public int CatalogueCount() => Catalogue.Count;

	/// <returns>id, title, kind, price, units, watts — one row, for the shop list.</returns>
	public Godot.Collections.Array Item(int index)
	{
		CatalogueItem item = Catalogue.At(index);
		return new Godot.Collections.Array
		{
			item.Id, item.Title, (int)item.Kind, item.Price, item.Units, item.Watts,
		};
	}

	public bool CanAfford(int index) => _money.CanAfford(Catalogue.At(index).Price);

	/// <summary>Charge for an item and queue the work that puts it there. Returns the
	/// job id, or -1 if it could not be paid for.</summary>
	/// <param name="place">Rack id for a server, floor spot for a cabinet — the queue
	/// passes it through and the scene decides what it means.</param>
	public int Buy(int index, int place, int slot)
	{
		CatalogueItem item = Catalogue.At(index);
		if (!_money.Spend(item.Price))
		{
			return -1;
		}
		// A cabinet is carried in and stood up; a server is racked and patched. The
		// second is the longer job even though it is the smaller thing.
		JobKind kind = item.Kind == ItemKind.Rack ? JobKind.InstallRack : JobKind.InstallServer;
		float seconds = item.Kind == ItemKind.Rack ? 22f : 14f;
		return _jobs.Add(kind, place, slot, seconds);
	}

	public int JobCount() => _jobs.Count;
	public int JobKindOf(int job) => (int)_jobs.KindOf(job);
	public int JobPlaceOf(int job) => _jobs.PlaceOf(job);
	public int JobSlotOf(int job) => _jobs.SlotOf(job);
	public int JobStateOf(int job) => (int)_jobs.StateOf(job);
	public int JobClaimOf(int job) => _jobs.ClaimOf(job);
	public float JobProgressOf(int job) => _jobs.ProgressOf(job);
	public int Claim(int worker) => _jobs.Claim(worker);
	public void Release(int job) => _jobs.Release(job);
	public bool Advance(int job, float seconds) => _jobs.Advance(job, seconds);
	public int JobsQueued() => _jobs.CountIn(JobState.Queued);
	public int JobsRunning() => _jobs.CountIn(JobState.Claimed);
	public int JobsDone() => _jobs.CountIn(JobState.Done);
}
