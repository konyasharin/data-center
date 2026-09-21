using DataCenter.Sim.Cabling;

namespace DataCenter.Sim.Tests;

/// <summary>
/// Walks a small hall through the thing the mechanic exists for: a rack wired by a
/// technician looks identical to one wired properly, right up to the moment a feed
/// is taken down for maintenance.
///
///     dotnet run --project tests/Sim.Tests -- demo
/// </summary>
internal static class Demo
{
	public static void Run()
	{
		const int racksInRow = 4;
		const int serversPerRack = 20;

		CablingState state = new();
		int[][] servers = new int[racksInRow][];
		int[] feedA = new int[racksInRow];
		int[] feedB = new int[racksInRow];
		int[] tops = new int[racksInRow];

		for (int rack = 0; rack < racksInRow; rack++)
		{
			servers[rack] = new int[serversPerRack];
			for (int i = 0; i < serversPerRack; i++)
			{
				servers[rack][i] = state.AddDevice(DeviceKind.Server, rack, 2, 1);
			}
			feedA[rack] = state.AddDevice(DeviceKind.Pdu, rack, 24, 0, Feed.A);
			feedB[rack] = state.AddDevice(DeviceKind.Pdu, rack, 24, 0, Feed.B);
			tops[rack] = state.AddDevice(DeviceKind.Switch, rack, 0, 48);
		}

		Console.WriteLine($"hall: {racksInRow} racks, {serversPerRack} servers each");
		Console.WriteLine();

		// racks 0 and 1 are patched by the player, 2 and 3 by a tired technician
		for (int rack = 0; rack < racksInRow; rack++)
		{
			bool byHand = rack < 2;
			WiringReport report = RackWiring.WireRack(state, servers[rack], feedA[rack],
				feedB[rack], tops[rack], mistakeIn: byHand ? 0 : 5, seed: (uint)(rack + 11));
			Console.WriteLine($"rack {rack} wired by {(byHand ? "the player " : "a technician")}"
				+ $"  power {report.PowerLinks,3}  network {report.NetworkLinks,3}"
				+ $"  slips {report.Mistakes}");
		}

		Console.WriteLine();
		Console.WriteLine("what the panel shows now:");
		Report(state, servers);

		Console.WriteLine();
		Console.WriteLine($"-- feed A goes down: {state.DisconnectFeed(Feed.A)} cords out --");
		Console.WriteLine();
		Report(state, servers);
		Console.WriteLine();
		Console.WriteLine("the racks that looked fine are the ones that stayed up.");
	}

	private static void Report(CablingState state, int[][] racks)
	{
		for (int rack = 0; rack < racks.Length; rack++)
		{
			int redundant = 0, single = 0, dark = 0, offline = 0, exposed = 0;
			foreach (int server in racks[rack])
			{
				ServerStatus status = state.StatusOf(server);
				switch (status.Power)
				{
					case PowerState.Redundant: redundant++; break;
					case PowerState.SinglePath: single++; break;
					default: dark++; break;
				}
				if (!status.Online) offline++;
				if (status.BothInletsOneFeed) exposed++;
			}
			Console.WriteLine($"  rack {rack}: redundant {redundant,2}  one path {single,2}"
				+ $"  dark {dark,2}  offline {offline,2}  on a single feed {exposed,2}");
		}
	}
}
