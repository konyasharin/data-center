namespace DataCenter.Sim.Cabling;

public readonly record struct WiringReport(
	int ServersWired,
	int PowerLinks,
	int NetworkLinks,
	int Mistakes,
	int OutOfPorts,
	int Refused);

/// <summary>
/// "Wire the rack" as one action.
///
/// Patching a rack by hand is the interesting thing exactly once. After that it is
/// forty identical motions, so the default is this: the rack gets wired in one go,
/// it costs time, and whoever does it can get it wrong. The player reaches in by
/// hand for the parts that matter — fixing a mistake, moving a server to another
/// switch, swapping a feed before maintenance.
/// </summary>
public static class RackWiring
{
	/// <param name="mistakeIn">One in N chance per server that the technician slips.
	/// Zero means a perfect job, which is what the player doing it themselves gets
	/// (docs/04-workers.md: the player does not make random errors).</param>
	public static WiringReport WireRack(CablingState state, ReadOnlySpan<int> servers,
		int pduA, int pduB, int uplink, int mistakeIn = 0, uint seed = 1)
	{
		return WireRack(state, servers, stackalloc int[] { pduA }, stackalloc int[] { pduB },
			stackalloc int[] { uplink }, mistakeIn, seed);
	}

	/// <summary>A real rack runs several PDU strips per feed and more than one switch,
	/// because one 16-outlet strip does not feed forty servers. Each side is tried in
	/// order and the first one with a socket left wins.</summary>
	public static WiringReport WireRack(CablingState state, ReadOnlySpan<int> servers,
		ReadOnlySpan<int> feedA, ReadOnlySpan<int> feedB, ReadOnlySpan<int> uplinks,
		int mistakeIn = 0, uint seed = 1)
	{
		int wired = 0, power = 0, network = 0, mistakes = 0, shortOfPorts = 0, refused = 0;
		uint rng = seed == 0 ? 1u : seed;

		for (int i = 0; i < servers.Length; i++)
		{
			int server = servers[i];
			bool slip = mistakeIn > 0 && NextBelow(ref rng, (uint)mistakeIn) == 0;
			int slipKind = slip ? (int)NextBelow(ref rng, 3) : -1;
			if (slip)
			{
				mistakes++;
			}

			// alternate which feed is taken first, so a half-wired rack is still
			// balanced across the two supplies
			ReadOnlySpan<int> first = (i & 1) == 0 ? feedA : feedB;
			ReadOnlySpan<int> second = (i & 1) == 0 ? feedB : feedA;
			if (slipKind == 1)
			{
				second = first;   // both inlets on one feed: works until that feed drops
			}

			// Where this server sits in the rack, as a fraction. Outlets and uplinks are
			// handed out from the matching point in their own row rather than from the
			// first free one, so a cord reaches the socket level with it instead of
			// crossing half the cabinet to the next one in order.
			float at = servers.Length > 1 ? i / (float)(servers.Length - 1) : 0f;

			int madeHere = 0;
			int inlets = slipKind == 0 ? 1 : 2;
			for (int inlet = 0; inlet < inlets; inlet++)
			{
				ReadOnlySpan<int> target = inlet == 0 ? first : second;
				int serverPort = state.FindFreePort(server, LineKind.Power);
				int pduPort = FreePortIn(state, target, LineKind.Power, at);
				if (serverPort < 0 || pduPort < 0)
				{
					shortOfPorts++;
					continue;
				}
				if (state.Connect(serverPort, pduPort, out _) == ConnectResult.Ok)
				{
					power++;
					madeHere++;
				}
				else
				{
					refused++;
				}
			}

			if (slipKind != 2)
			{
				int serverPort = state.FindFreePort(server, LineKind.Network);
				int switchPort = FreePortIn(state, uplinks, LineKind.Network, at);
				if (serverPort < 0 || switchPort < 0)
				{
					shortOfPorts++;
				}
				else if (state.Connect(serverPort, switchPort, out _) == ConnectResult.Ok)
				{
					network++;
					madeHere++;
				}
				else
				{
					refused++;
				}
			}

			// A server nothing could be attached to is not a wired server. Counting it
			// as one let a report say "all 20 done" for a rack with no outlets left.
			if (madeHere > 0)
			{
				wired++;
			}
		}

		return new WiringReport(wired, power, network, mistakes, shortOfPorts, refused);
	}

	/// <param name="at">Where to start looking, as a fraction of the device's ports.
	/// Both sides are ordered the same way — servers up the rack, outlets up the strip
	/// — so starting level with the server keeps the cords short and parallel instead
	/// of letting them cross each other on the way to the next free socket.</param>
	private static int FreePortIn(CablingState state, ReadOnlySpan<int> devices,
		LineKind line, float at = 0f)
	{
		foreach (int device in devices)
		{
			int count = state.PortCountOf(device);
			if (count == 0)
			{
				continue;
			}
			int start = Math.Clamp((int)(at * (count - 1)), 0, count - 1);
			for (int step = 0; step < count; step++)
			{
				int port = state.PortOf(device, (start + step) % count);
				if (state.LineOf(port) == line && state.IsFree(port))
				{
					return port;
				}
			}
		}
		return -1;
	}

	/// <summary>xorshift32: small, allocation-free and repeatable, which matters
	/// because the same seed has to rebuild the same hall after a save/load.</summary>
	private static uint NextBelow(ref uint state, uint bound)
	{
		state ^= state << 13;
		state ^= state >> 17;
		state ^= state << 5;
		return bound == 0 ? 0 : state % bound;
	}
}
