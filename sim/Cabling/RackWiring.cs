namespace DataCenter.Sim.Cabling;

public readonly record struct WiringReport(
	int ServersWired,
	int PowerLinks,
	int NetworkLinks,
	int Mistakes,
	int OutOfPorts);

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
		int wired = 0, power = 0, network = 0, mistakes = 0, shortOfPorts = 0;
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
			int first = (i & 1) == 0 ? pduA : pduB;
			int second = (i & 1) == 0 ? pduB : pduA;
			if (slipKind == 1)
			{
				second = first;   // both inlets on one feed: works until that feed drops
			}

			int inlets = slipKind == 0 ? 1 : 2;
			for (int inlet = 0; inlet < inlets; inlet++)
			{
				int target = inlet == 0 ? first : second;
				int serverPort = state.FindFreePort(server, LineKind.Power);
				int pduPort = state.FindFreePort(target, LineKind.Power);
				if (serverPort < 0 || pduPort < 0)
				{
					shortOfPorts++;
					continue;
				}
				if (state.Connect(serverPort, pduPort, out _) == ConnectResult.Ok)
				{
					power++;
				}
			}

			if (slipKind != 2)
			{
				int serverPort = state.FindFreePort(server, LineKind.Network);
				int switchPort = state.FindFreePort(uplink, LineKind.Network);
				if (serverPort < 0 || switchPort < 0)
				{
					shortOfPorts++;
				}
				else if (state.Connect(serverPort, switchPort, out _) == ConnectResult.Ok)
				{
					network++;
				}
			}

			wired++;
		}

		return new WiringReport(wired, power, network, mistakes, shortOfPorts);
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
