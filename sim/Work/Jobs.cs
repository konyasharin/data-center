namespace DataCenter.Sim.Work;

public enum JobKind : byte
{
	InstallServer,
	InstallRack,
}

public enum JobState : byte
{
	Queued,
	Claimed,
	Done,
}

/// <summary>
/// Everything that happens in the world is a job in this queue (docs/04-workers.md).
///
/// Jobs are rows in parallel arrays, not objects, and they are never removed: a
/// finished job keeps its index so anything holding one — a worker on the way, a tag
/// hanging on a rack, a line in the log — is still looking at the same job. The queue
/// only ever grows, which is also what makes it trivial to serialize.
/// </summary>
public sealed class JobQueue
{
	private JobKind[] _kind = Array.Empty<JobKind>();
	private int[] _place = Array.Empty<int>();
	private int[] _slot = Array.Empty<int>();
	private JobState[] _state = Array.Empty<JobState>();
	private int[] _claim = Array.Empty<int>();
	private float[] _left = Array.Empty<float>();
	private float[] _work = Array.Empty<float>();
	private int _count;

	public int Count => _count;

	/// <param name="place">Where the work is: a rack id for a server, a floor spot for
	/// a cabinet. The queue does not know what either means.</param>
	/// <param name="seconds">How long the work takes once someone is standing there.</param>
	public int Add(JobKind kind, int place, int slot, float seconds)
	{
		ArgumentOutOfRangeException.ThrowIfNegativeOrZero(seconds);

		int id = _count++;
		Grow(ref _kind, _count);
		Grow(ref _place, _count);
		Grow(ref _slot, _count);
		Grow(ref _state, _count);
		Grow(ref _claim, _count);
		Grow(ref _left, _count);
		Grow(ref _work, _count);

		_kind[id] = kind;
		_place[id] = place;
		_slot[id] = slot;
		_state[id] = JobState.Queued;
		_claim[id] = -1;
		_left[id] = seconds;
		_work[id] = seconds;
		return id;
	}

	public JobKind KindOf(int job) => _kind[Job(job)];
	public int PlaceOf(int job) => _place[Job(job)];
	public int SlotOf(int job) => _slot[Job(job)];
	public JobState StateOf(int job) => _state[Job(job)];
	public int ClaimOf(int job) => _claim[Job(job)];
	public float LeftOf(int job) => _left[Job(job)];

	/// <summary>How far along the work is, 0 to 1. What a progress bar on the laptop
	/// reads, and what decides when a body stops playing its animation.</summary>
	public float ProgressOf(int job)
	{
		int id = Job(job);
		return _work[id] <= 0f ? 1f : 1f - (_left[id] / _work[id]);
	}

	/// <summary>The oldest job nobody has taken. First in, first done: a real priority
	/// rule needs skills, travel time and fatigue, and none of those exist yet — a
	/// made-up score now would be a rule to unpick later.</summary>
	public int Claim(int worker)
	{
		return ClaimJob(NextQueued(0), worker) ? NextClaimed(worker) : -1;
	}

	/// <summary>The next unclaimed job at or after <paramref name="from"/>, or -1.
	/// Taking the oldest is only right while every job can be done: a worker who cannot
	/// get to the oldest one — somebody else is standing in that aisle — has to be able
	/// to look past it instead of waiting for it.</summary>
	public int NextQueued(int from)
	{
		for (int job = Math.Max(0, from); job < _count; job++)
		{
			if (_state[job] == JobState.Queued)
			{
				return job;
			}
		}
		return -1;
	}

	public bool ClaimJob(int job, int worker)
	{
		if (job < 0 || job >= _count || _state[job] != JobState.Queued)
		{
			return false;
		}
		_state[job] = JobState.Claimed;
		_claim[job] = worker;
		return true;
	}

	private int NextClaimed(int worker)
	{
		for (int job = 0; job < _count; job++)
		{
			if (_state[job] == JobState.Claimed && _claim[job] == worker)
			{
				return job;
			}
		}
		return -1;
	}

	public void Release(int job)
	{
		int id = Job(job);
		if (_state[id] != JobState.Claimed)
		{
			return;
		}
		_state[id] = JobState.Queued;
		_claim[id] = -1;
	}

	/// <summary>Advance a claimed job and say whether it has just finished. Clamped
	/// rather than stepped: a tick can be an hour and a half of game time
	/// (CLAUDE.md, rule 4), and work must not overshoot into the next job.</summary>
	public bool Advance(int job, float seconds)
	{
		ArgumentOutOfRangeException.ThrowIfNegative(seconds);
		int id = Job(job);
		if (_state[id] != JobState.Claimed)
		{
			return false;
		}
		_left[id] = Math.Max(0f, _left[id] - seconds);
		if (_left[id] > 0f)
		{
			return false;
		}
		_state[id] = JobState.Done;
		return true;
	}

	public int CountIn(JobState state)
	{
		int seen = 0;
		for (int job = 0; job < _count; job++)
		{
			if (_state[job] == state)
			{
				seen++;
			}
		}
		return seen;
	}

	private int Job(int job)
	{
		ArgumentOutOfRangeException.ThrowIfNegative(job);
		ArgumentOutOfRangeException.ThrowIfGreaterThanOrEqual(job, _count);
		return job;
	}

	private static void Grow<T>(ref T[] array, int needed)
	{
		if (array.Length >= needed)
		{
			return;
		}
		int size = array.Length == 0 ? 16 : array.Length;
		while (size < needed)
		{
			size *= 2;
		}
		Array.Resize(ref array, size);
	}
}
