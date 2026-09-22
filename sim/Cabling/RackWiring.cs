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
			bool slip = mistakeIn > 0 && NextBelow(ref rng, (uint)mistakeIn) == 0;
			int slipKind = slip ? (int)NextBelow(ref rng, 3) : -1;
			if (slip)
			{
				mistakes++;
			}

			ServerWiring made = WireOne(state, servers, i, feedA, feedB, uplinks, slipKind);
			power += made.Power;
			network += made.Network;
			shortOfPorts += made.Short;
			refused += made.Refused;
			// A server nothing could be attached to is not a wired server. Counting it
			// as one let a report say "all 20 done" for a rack with no outlets left.
			if (made.Power + made.Network > 0)
			{
				wired++;
			}
		}

		return new WiringReport(wired, power, network, mistakes, shortOfPorts, refused);
	}

	/// <summary>One server, patched by the same rules as a whole rack. This is what a
	/// technician racking a single box does, and it has to agree with the rack pass
	/// exactly — where a server's cords go depends on where it sits among its
	/// neighbours, so `index` is its place in the rack and not a loop counter.</summary>
	public static WiringReport WireServer(CablingState state, ReadOnlySpan<int> servers,
		int index, ReadOnlySpan<int> feedA, ReadOnlySpan<int> feedB,
		ReadOnlySpan<int> uplinks)
	{
		ArgumentOutOfRangeException.ThrowIfNegative(index);
		ArgumentOutOfRangeException.ThrowIfGreaterThanOrEqual(index, servers.Length);

		ServerWiring made = WireOne(state, servers, index, feedA, feedB, uplinks, -1);
		return new WiringReport(made.Power + made.Network > 0 ? 1 : 0, made.Power,
			made.Network, 0, made.Short, made.Refused);
	}

	private readonly record struct ServerWiring(int Power, int Network, int Short, int Refused);

	/// <param name="slipKind">-1 for a clean job; 0 leaves one inlet unplugged, 1 puts
	/// both on the same feed, 2 forgets the network.</param>
	private static ServerWiring WireOne(CablingState state, ReadOnlySpan<int> servers,
		int i, ReadOnlySpan<int> feedA, ReadOnlySpan<int> feedB, ReadOnlySpan<int> uplinks,
		int slipKind)
	{
		int server = servers[i];
		int power = 0, network = 0, shortOfPorts = 0, refused = 0;

		// The left inlet always takes feed A and the right one feed B. Alternating
		// them per server is just as redundant and reads as a mistake: the two cords
		// leaving a server cross, and the pair of ducts fills with cords arriving from
		// opposite inlets.
		ReadOnlySpan<int> first = feedA;
		ReadOnlySpan<int> second = slipKind == 1 ? feedA : feedB;

		int inlets = slipKind == 0 ? 1 : 2;
		for (int inlet = 0; inlet < inlets; inlet++)
		{
			ReadOnlySpan<int> target = inlet == 0 ? first : second;
			int serverPort = state.FindFreePort(server, LineKind.Power);
			int pduPort = FreePortIn(state, target, LineKind.Power, i);
			if (serverPort < 0 || pduPort < 0)
			{
				shortOfPorts++;
				continue;
			}
			if (state.Connect(serverPort, pduPort, out _) == ConnectResult.Ok)
			{
				power++;
			}
			else
			{
				refused++;
			}
		}

		if (slipKind != 2)
		{
			// The rack is split down the middle: the lower servers climb one duct and
			// take the switch from one end, the upper ones climb the other and take it
			// from the other end. One duct carrying every network cord is a stuffed
			// bundle beside an empty channel, and half of those cords then cross the
			// whole panel to reach their socket.
			bool lower = i < servers.Length / 2;
			int serverPort = state.FindFreePort(server, LineKind.Network);
			int switchPort = UplinkPort(state, uplinks,
				lower ? i : i - servers.Length / 2, lower);
			if (serverPort < 0 || switchPort < 0)
			{
				shortOfPorts++;
			}
			else if (state.Connect(serverPort, switchPort, out _) == ConnectResult.Ok)
			{
				network++;
			}
			else
			{
				refused++;
			}
		}

		return new ServerWiring(power, network, shortOfPorts, refused);
	}

	/// <param name="nth">Which socket to start looking at. Both sides are ordered the
	/// same way — servers up the rack, outlets up the strip — so the nth server takes
	/// the nth outlet and every cord in the rack runs parallel to its neighbours. Any
	/// other rule, including spreading the servers evenly over the outlets, makes the
	/// cords fan instead.</param>
	private static int FreePortIn(CablingState state, ReadOnlySpan<int> devices,
		LineKind line, int nth = 0)
	{
		foreach (int device in devices)
		{
			int count = state.PortCountOf(device);
			if (count == 0)
			{
				continue;
			}
			int start = Math.Clamp(nth, 0, count - 1);
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

	/// <summary>A socket on the uplink, taken column by column from one end of the
	/// panel: both rows of the first column, then both rows of the next. Going along a
	/// row instead spreads one server's neighbours across the whole panel, and the
	/// cords cross on their way up.</summary>
	/// <param name="nth">Which server of its half of the rack this is.</param>
	/// <param name="fromStart">Which end of the panel to fill from.</param>
	private static int UplinkPort(CablingState state, ReadOnlySpan<int> uplinks,
		int nth, bool fromStart)
	{
		foreach (int device in uplinks)
		{
			int count = state.PortCountOf(device);
			int rows = state.RowsOf(device);
			int perRow = rows == 0 ? 0 : count / rows;
			if (perRow == 0)
			{
				continue;
			}
			for (int step = 0; step < count; step++)
			{
				int k = nth + step;
				int column = k / rows;
				if (column >= perRow)
				{
					break;
				}
				// The two halves start on opposite rows, so the panel fills
				// symmetrically about its middle: each half takes the row nearest the
				// duct its cords come up first.
				int row = fromStart ? rows - 1 - (k % rows) : k % rows;
				int port = state.PortOf(device,
					row * perRow + (fromStart ? column : perRow - 1 - column));
				if (state.LineOf(port) == LineKind.Network && state.IsFree(port))
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
