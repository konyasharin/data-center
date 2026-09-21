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

	// ---------------------------------------------------------------- harness

	private static void Check(string what, bool ok)
	{
		Console.WriteLine($"  {(ok ? "ok  " : "FAIL")}  {what}");
		if (!ok)
		{
			_failures++;
		}
	}
}
