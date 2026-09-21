using DataCenter.Sim.Cabling;
using Godot;

namespace DataCenter;

/// <summary>
/// The scene's handle on <see cref="CablingState"/>.
///
/// The core knows nothing about Godot and must keep it that way (docs/10), so the
/// engine side talks to it through this: ints in, ints out, no simulation logic of
/// its own. Every rule — what may plug into what, how far a cable reaches, whether
/// a server counts as fed — stays on the other side of this file.
/// </summary>
[GlobalClass]
public partial class CablingBridge : RefCounted
{
	// Status packed into one int rather than a Dictionary per server: the scene reads
	// this for every server in the hall whenever the wiring changes.
	public const int PowerMask = 0x3;
	public const int OnlineBit = 1 << 2;
	public const int OneFeedBit = 1 << 3;

	private readonly CablingState _state = new();

	public int LastLink { get; private set; } = -1;

	public int AddDevice(int kind, int rack, int powerPorts, int networkPorts, int feed)
	{
		return _state.AddDevice((DeviceKind)kind, rack, powerPorts, networkPorts, (Feed)feed);
	}

	public int DeviceCount() => _state.DeviceCount;
	public int KindOf(int device) => (int)_state.KindOf(device);
	public int RackOf(int device) => _state.RackOf(device);
	public int FeedOf(int device) => (int)_state.FeedOf(device);
	public int PortCountOf(int device) => _state.PortCountOf(device);
	public int PortOf(int device, int index) => _state.PortOf(device, index);
	public int FindFreePort(int device, int line) => _state.FindFreePort(device, (LineKind)line);

	public int LineOf(int port) => (int)_state.LineOf(port);
	public int OwnerOf(int port) => _state.OwnerOf(port);
	public bool IsFree(int port) => _state.IsFree(port);
	public int LinkOf(int port) => _state.LinkOf(port);
	public int OtherEnd(int port) => _state.OtherEnd(port);

	public int CanConnect(int portA, int portB) => (int)_state.CanConnect(portA, portB);

	public int Connect(int portA, int portB)
	{
		ConnectResult result = _state.Connect(portA, portB, out int link);
		LastLink = link;
		return (int)result;
	}

	public bool Disconnect(int link) => _state.Disconnect(link);
	public int DisconnectFeed(int feed) => _state.DisconnectFeed((Feed)feed);

	public int Status(int server)
	{
		ServerStatus status = _state.StatusOf(server);
		return (int)status.Power
			| (status.Online ? OnlineBit : 0)
			| (status.BothInletsOneFeed ? OneFeedBit : 0);
	}

	/// <summary>Every live link as a flat run of port pairs — what the cable geometry
	/// is rebuilt from, which only happens when the patching actually changes.</summary>
	public int[] LiveLinks()
	{
		int live = 0;
		for (int link = 0; link < _state.LinkCount; link++)
		{
			if (_state.LinkLive(link))
			{
				live++;
			}
		}

		int[] pairs = new int[live * 2];
		int at = 0;
		for (int link = 0; link < _state.LinkCount; link++)
		{
			if (_state.LinkLive(link))
			{
				pairs[at++] = _state.LinkPortA(link);
				pairs[at++] = _state.LinkPortB(link);
			}
		}
		return pairs;
	}

	/// <param name="report">wired, power, network, mistakes, out-of-ports, refused.</param>
	public int[] WireRack(int[] servers, int[] feedA, int[] feedB, int[] uplinks,
		int mistakeIn, int seed)
	{
		WiringReport report = RackWiring.WireRack(_state, servers, feedA, feedB, uplinks,
			mistakeIn, (uint)seed);
		return new[]
		{
			report.ServersWired, report.PowerLinks, report.NetworkLinks,
			report.Mistakes, report.OutOfPorts, report.Refused,
		};
	}
}
