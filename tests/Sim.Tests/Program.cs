using DataCenter.Sim.Cabling;

namespace DataCenter.Sim.Tests;

internal static class Program
{
	private static int _failures;

	private static int Main(string[] args)
	{
		if (args.Length > 0 && args[0] == "demo")
		{
			Demo.Run();
			return 0;
		}

		PowerOnTwoFeedsIsRedundant();
		BothInletsOneFeedIsFlagged();
		OccupiedPortIsRefused();
		PowerDoesNotCrossRacks();
		NetworkReachesTheNextRackOnly();
		MixedLineKindsAreRefused();
		DisconnectFreesBothPorts();
		WiringARackAlternatesFeeds();
		MistakesLeaveServersWorkingButExposed();
		RunningOutOfOutletsIsReported();
		PowerBetweenServersIsRefused();
		ConnectingADeviceToItselfIsRefused();
		AFullRackReportsNoFreePort();
		APortIsReusableOnceFreed();
		WiringIsRepeatable();
		StaleIdsAreRejected();
		MaintenanceOnFeedA();

		Console.WriteLine(_failures == 0
			? "\ncabling: all checks passed"
			: $"\ncabling: {_failures} FAILED");
		return _failures == 0 ? 0 : 1;
	}

	// ---------------------------------------------------------------- cases

	private static void PowerOnTwoFeedsIsRedundant()
	{
		CablingState s = new();
		int server = s.AddDevice(DeviceKind.Server, rack: 0, powerPorts: 2, networkPorts: 1);
		int pduA = s.AddDevice(DeviceKind.Pdu, 0, 24, 0, Feed.A);
		int pduB = s.AddDevice(DeviceKind.Pdu, 0, 24, 0, Feed.B);

		Check("unwired server is dark", s.StatusOf(server).Power == PowerState.Unpowered);

		s.Connect(s.FindFreePort(server, LineKind.Power), s.FindFreePort(pduA, LineKind.Power), out _);
		Check("one inlet is single path", s.StatusOf(server).Power == PowerState.SinglePath);

		s.Connect(s.FindFreePort(server, LineKind.Power), s.FindFreePort(pduB, LineKind.Power), out _);
		ServerStatus status = s.StatusOf(server);
		Check("A plus B is redundant", status.Power == PowerState.Redundant);
		Check("redundant is not flagged", !status.BothInletsOneFeed);
		Check("no switch means offline", !status.Online);
	}

	private static void BothInletsOneFeedIsFlagged()
	{
		CablingState s = new();
		int server = s.AddDevice(DeviceKind.Server, 0, 2, 1);
		int pduA = s.AddDevice(DeviceKind.Pdu, 0, 24, 0, Feed.A);
		s.AddDevice(DeviceKind.Pdu, 0, 24, 0, Feed.B);

		s.Connect(s.FindFreePort(server, LineKind.Power), s.FindFreePort(pduA, LineKind.Power), out _);
		s.Connect(s.FindFreePort(server, LineKind.Power), s.FindFreePort(pduA, LineKind.Power), out _);

		ServerStatus status = s.StatusOf(server);
		Check("two inlets on one feed still powers the box", status.Power == PowerState.SinglePath);
		Check("and it is flagged", status.BothInletsOneFeed);
	}

	private static void OccupiedPortIsRefused()
	{
		CablingState s = new();
		int a = s.AddDevice(DeviceKind.Server, 0, 2, 1);
		int b = s.AddDevice(DeviceKind.Server, 0, 2, 1);
		int pdu = s.AddDevice(DeviceKind.Pdu, 0, 1, 0, Feed.A);

		int outlet = s.FindFreePort(pdu, LineKind.Power);
		s.Connect(s.FindFreePort(a, LineKind.Power), outlet, out _);
		Check("the only outlet is taken", s.FindFreePort(pdu, LineKind.Power) < 0);
		Check("re-using it is refused",
			s.Connect(s.FindFreePort(b, LineKind.Power), outlet, out _) == ConnectResult.PortOccupied);
	}

	private static void PowerDoesNotCrossRacks()
	{
		CablingState s = new();
		int server = s.AddDevice(DeviceKind.Server, 0, 2, 1);
		int pdu = s.AddDevice(DeviceKind.Pdu, 1, 24, 0, Feed.A);
		Check("power stays in its rack",
			s.Connect(s.FindFreePort(server, LineKind.Power), s.FindFreePort(pdu, LineKind.Power),
				out _) == ConnectResult.OutOfReach);
	}

	private static void NetworkReachesTheNextRackOnly()
	{
		CablingState s = new();
		int server = s.AddDevice(DeviceKind.Server, 0, 2, 1);
		int near = s.AddDevice(DeviceKind.Switch, 1, 0, 48);
		int far = s.AddDevice(DeviceKind.Switch, 3, 0, 48);

		Check("neighbouring rack is fine",
			s.Connect(s.FindFreePort(server, LineKind.Network), s.FindFreePort(near, LineKind.Network),
				out _) == ConnectResult.Ok);
		int second = s.AddDevice(DeviceKind.Server, 0, 2, 1);
		Check("three racks away is not",
			s.Connect(s.FindFreePort(second, LineKind.Network), s.FindFreePort(far, LineKind.Network),
				out _) == ConnectResult.OutOfReach);
	}

	private static void MixedLineKindsAreRefused()
	{
		CablingState s = new();
		int server = s.AddDevice(DeviceKind.Server, 0, 2, 1);
		int sw = s.AddDevice(DeviceKind.Switch, 0, 0, 48);
		Check("a patch cord does not go in an outlet",
			s.Connect(s.FindFreePort(server, LineKind.Power), s.FindFreePort(sw, LineKind.Network),
				out _) == ConnectResult.MixedLineKinds);
	}

	private static void DisconnectFreesBothPorts()
	{
		CablingState s = new();
		int server = s.AddDevice(DeviceKind.Server, 0, 2, 1);
		int pdu = s.AddDevice(DeviceKind.Pdu, 0, 24, 0, Feed.A);

		int serverPort = s.FindFreePort(server, LineKind.Power);
		int outlet = s.FindFreePort(pdu, LineKind.Power);
		s.Connect(serverPort, outlet, out int link);
		Check("pulling it out works", s.Disconnect(link));
		Check("server port is free again", s.IsFree(serverPort));
		Check("outlet is free again", s.IsFree(outlet));
		Check("server went dark", s.StatusOf(server).Power == PowerState.Unpowered);
		Check("pulling twice does nothing", !s.Disconnect(link));
	}

	private static void WiringARackAlternatesFeeds()
	{
		CablingState s = new();
		int[] servers = new int[20];
		for (int i = 0; i < servers.Length; i++)
		{
			servers[i] = s.AddDevice(DeviceKind.Server, 0, 2, 1);
		}
		int pduA = s.AddDevice(DeviceKind.Pdu, 0, 24, 0, Feed.A);
		int pduB = s.AddDevice(DeviceKind.Pdu, 0, 24, 0, Feed.B);
		int top = s.AddDevice(DeviceKind.Switch, 0, 0, 48);

		WiringReport report = RackWiring.WireRack(s, servers, pduA, pduB, top);

		Check("every server wired", report.ServersWired == servers.Length);
		Check("two inlets each", report.PowerLinks == servers.Length * 2);
		Check("one uplink each", report.NetworkLinks == servers.Length);
		Check("no mistakes when the player does it", report.Mistakes == 0);

		bool allGood = true;
		foreach (int server in servers)
		{
			ServerStatus status = s.StatusOf(server);
			allGood &= status.Power == PowerState.Redundant && status.Online;
		}
		Check("all redundant and online", allGood);
	}

	private static void MistakesLeaveServersWorkingButExposed()
	{
		CablingState s = new();
		int[] servers = new int[40];
		for (int i = 0; i < servers.Length; i++)
		{
			servers[i] = s.AddDevice(DeviceKind.Server, 0, 2, 1);
		}
		int pduA = s.AddDevice(DeviceKind.Pdu, 0, 48, 0, Feed.A);
		int pduB = s.AddDevice(DeviceKind.Pdu, 0, 48, 0, Feed.B);
		int top = s.AddDevice(DeviceKind.Switch, 0, 0, 48);

		WiringReport report = RackWiring.WireRack(s, servers, pduA, pduB, top, mistakeIn: 4, seed: 7);
		Check("a sloppy technician makes some", report.Mistakes > 0);

		int exposed = 0, offline = 0, dark = 0;
		foreach (int server in servers)
		{
			ServerStatus status = s.StatusOf(server);
			if (status.BothInletsOneFeed) exposed++;
			if (!status.Online) offline++;
			if (status.Power == PowerState.Unpowered) dark++;
		}
		Check("some are quietly on one feed", exposed > 0);
		Check("nothing is left dark", dark == 0);
		Check("mistakes are invisible from the panel", exposed + offline <= report.Mistakes);
	}

	private static void RunningOutOfOutletsIsReported()
	{
		CablingState s = new();
		int[] servers = new int[10];
		for (int i = 0; i < servers.Length; i++)
		{
			servers[i] = s.AddDevice(DeviceKind.Server, 0, 2, 1);
		}
		int pduA = s.AddDevice(DeviceKind.Pdu, 0, 4, 0, Feed.A);
		int pduB = s.AddDevice(DeviceKind.Pdu, 0, 4, 0, Feed.B);
		int top = s.AddDevice(DeviceKind.Switch, 0, 0, 4);

		WiringReport report = RackWiring.WireRack(s, servers, pduA, pduB, top);
		Check("the shortfall is counted", report.OutOfPorts > 0);
		Check("it wired what it could", report.PowerLinks == 8 && report.NetworkLinks == 4);
	}

	private static void PowerBetweenServersIsRefused()
	{
		CablingState s = new();
		int a = s.AddDevice(DeviceKind.Server, 0, 2, 1);
		int b = s.AddDevice(DeviceKind.Server, 0, 2, 1);
		Check("a server is not a power source",
			s.Connect(s.FindFreePort(a, LineKind.Power), s.FindFreePort(b, LineKind.Power),
				out _) == ConnectResult.PowerNeedsPdu);
		Check("and neither of them reports power",
			s.StatusOf(a).Power == PowerState.Unpowered
			&& s.StatusOf(b).Power == PowerState.Unpowered);

		// the same check must not block a legitimate patch between two servers
		Check("but they may still be networked together",
			s.Connect(s.FindFreePort(a, LineKind.Network), s.FindFreePort(b, LineKind.Network),
				out _) == ConnectResult.Ok);
		Check("which does not make them online", !s.StatusOf(a).Online);
	}

	private static void ConnectingADeviceToItselfIsRefused()
	{
		CablingState s = new();
		int server = s.AddDevice(DeviceKind.Server, 0, 2, 2);
		Check("a cable into its own device is refused",
			s.Connect(s.PortOf(server, 2), s.PortOf(server, 3), out _) == ConnectResult.SameDevice);
	}

	private static void AFullRackReportsNoFreePort()
	{
		CablingState s = new();
		int server = s.AddDevice(DeviceKind.Server, 0, 2, 1);
		int pdu = s.AddDevice(DeviceKind.Pdu, 0, 1, 0, Feed.A);
		s.Connect(s.FindFreePort(server, LineKind.Power), s.FindFreePort(pdu, LineKind.Power), out _);

		// FindFreePort hands back -1 here, and "nothing left to plug into" has to read
		// differently from a bad index or the UI cannot say anything useful
		Check("out of outlets is its own answer",
			s.Connect(s.FindFreePort(server, LineKind.Power), s.FindFreePort(pdu, LineKind.Power),
				out _) == ConnectResult.NoFreePort);
		Check("a nonsense index is not the same answer",
			s.Connect(s.FindFreePort(server, LineKind.Power), 9999, out _)
				== ConnectResult.UnknownPort);
	}

	private static void APortIsReusableOnceFreed()
	{
		CablingState s = new();
		int server = s.AddDevice(DeviceKind.Server, 0, 2, 1);
		int pduA = s.AddDevice(DeviceKind.Pdu, 0, 1, 0, Feed.A);
		int pduB = s.AddDevice(DeviceKind.Pdu, 0, 1, 0, Feed.B);

		int inlet = s.FindFreePort(server, LineKind.Power);
		s.Connect(inlet, s.FindFreePort(pduA, LineKind.Power), out int first);
		Check("the port knows its cable", s.LinkOf(inlet) == first);
		Check("and where it goes", s.OwnerOf(s.OtherEnd(inlet)) == pduA);

		s.Disconnect(first);
		Check("a freed port has no cable", s.LinkOf(inlet) == -1 && s.OtherEnd(inlet) == -1);
		Check("moving the inlet to the other feed works",
			s.Connect(inlet, s.FindFreePort(pduB, LineKind.Power), out int second)
				== ConnectResult.Ok && second != first);
		Check("the dead link stays dead", !s.LinkLive(first) && s.LinkPortA(first) == -1);
	}

	private static void WiringIsRepeatable()
	{
		// the seed has to rebuild the same rack, or a save cannot store the wiring as
		// a seed plus the player's corrections
		WiringReport Once()
		{
			CablingState s = new();
			int[] servers = new int[30];
			for (int i = 0; i < servers.Length; i++)
			{
				servers[i] = s.AddDevice(DeviceKind.Server, 0, 2, 1);
			}
			int pduA = s.AddDevice(DeviceKind.Pdu, 0, 48, 0, Feed.A);
			int pduB = s.AddDevice(DeviceKind.Pdu, 0, 48, 0, Feed.B);
			int top = s.AddDevice(DeviceKind.Switch, 0, 0, 48);
			return RackWiring.WireRack(s, servers, pduA, pduB, top, mistakeIn: 4, seed: 99);
		}
		Check("the same seed wires the same rack", Once() == Once());
	}

	private static void StaleIdsAreRejected()
	{
		CablingState s = new();
		int server = s.AddDevice(DeviceKind.Server, 0, 2, 1);
		Check("a device id past the end throws", Throws(() => s.KindOf(server + 1)));
		// Feed.None is 0 on purpose: a stale id must not read as "on feed A"
		Check("a stale feed lookup throws rather than answering A",
			Throws(() => s.FeedOf(server + 5)));
		Check("a port index past the device throws", Throws(() => s.PortOf(server, 3)));
		Check("an unknown port throws", Throws(() => s.LineOf(9999)));
	}

	private static void MaintenanceOnFeedA()
	{
		// the whole point of the mechanic, in one case: two racks that read the same
		// on the panel come apart the moment a supply is taken down
		CablingState s = new();
		int[][] racks = new int[2][];
		int[] pduA = new int[2];
		int[] pduB = new int[2];
		for (int rack = 0; rack < 2; rack++)
		{
			racks[rack] = new int[20];
			for (int i = 0; i < 20; i++)
			{
				racks[rack][i] = s.AddDevice(DeviceKind.Server, rack, 2, 1);
			}
			pduA[rack] = s.AddDevice(DeviceKind.Pdu, rack, 24, 0, Feed.A);
			pduB[rack] = s.AddDevice(DeviceKind.Pdu, rack, 24, 0, Feed.B);
			int top = s.AddDevice(DeviceKind.Switch, rack, 0, 48);
			// the seed is picked so the sloppy rack is exposed but not already short of
			// outlets: both inlets on one feed uses a second socket there, and enough of
			// those in one rack run feed A out and take a server down before the sweep,
			// which is a different story from the one this case is about
			RackWiring.WireRack(s, racks[rack], pduA[rack], pduB[rack], top,
				mistakeIn: rack == 0 ? 0 : 3, seed: 1);
		}

		int sloppyExposed = Count(s, racks[1], st => st.BothInletsOneFeed);
		Check("the sloppy rack has servers on one feed", sloppyExposed > 0);
		Check("both racks look powered beforehand",
			Count(s, racks[0], st => st.Power == PowerState.Unpowered) == 0
			&& Count(s, racks[1], st => st.Power == PowerState.Unpowered) == 0);

		// who is holding a cord to the surviving feed, counted before the sweep
		int[] expectedDark = new int[2];
		for (int rack = 0; rack < 2; rack++)
		{
			foreach (int server in racks[rack])
			{
				if (!FedBy(s, server, Feed.B))
				{
					expectedDark[rack]++;
				}
			}
		}

		int pulled = s.DisconnectFeed(Feed.A);
		Check("taking a feed down pulls cords", pulled > 0);

		Check("the clean rack keeps every server up",
			Count(s, racks[0], st => st.Power == PowerState.Unpowered) == 0);
		Check("and every one of them is now on a single path",
			Count(s, racks[0], st => st.Power == PowerState.SinglePath) == racks[0].Length);
		Check("the clean rack had nothing riding on feed A alone", expectedDark[0] == 0);

		int dark = Count(s, racks[1], st => st.Power == PowerState.Unpowered);
		Check("the sloppy rack loses servers", dark > 0);
		Check("exactly the ones with no cord to feed B", dark == expectedDark[1]);
		Check("nothing that survived is redundant now",
			Count(s, racks[1], st => st.Power == PowerState.Redundant) == 0);
	}

	// ---------------------------------------------------------------- harness

	private static int Count(CablingState s, int[] servers, Func<ServerStatus, bool> match)
	{
		int n = 0;
		foreach (int server in servers)
		{
			if (match(s.StatusOf(server)))
			{
				n++;
			}
		}
		return n;
	}

	private static bool FedBy(CablingState s, int server, Feed feed)
	{
		for (int i = 0; i < s.PortCountOf(server); i++)
		{
			int port = s.PortOf(server, i);
			if (s.LineOf(port) != LineKind.Power)
			{
				continue;
			}
			int other = s.OtherEnd(port);
			if (other >= 0 && s.FeedOf(s.OwnerOf(other)) == feed)
			{
				return true;
			}
		}
		return false;
	}

	private static bool Throws(Action action)
	{
		try
		{
			action();
			return false;
		}
		catch (ArgumentOutOfRangeException)
		{
			return true;
		}
	}


	private static void Check(string what, bool ok)
	{
		Console.WriteLine($"  {(ok ? "ok  " : "FAIL")}  {what}");
		if (!ok)
		{
			_failures++;
		}
	}
}
