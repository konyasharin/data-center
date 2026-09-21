namespace DataCenter.Sim.Cabling;

public enum DeviceKind : byte
{
	Server,
	Pdu,
	Switch,
	PatchPanel,
}

/// <summary>Two line types only. Management shares the network ports, and copper
/// versus fibre is a reach question the rules already answer.</summary>
public enum LineKind : byte
{
	Power,
	Network,
}

/// <summary>Which supply path a PDU hangs off. A server with both inlets on the same
/// feed runs fine until that feed is worked on, which is the whole point.</summary>
public enum Feed : byte
{
	A,
	B,
	None,
}

public enum ConnectResult : byte
{
	Ok,
	MixedLineKinds,
	PortOccupied,
	SameDevice,
	OutOfReach,
	NoFreePort,
	UnknownPort,
}

public enum PowerState : byte
{
	Unpowered,
	SinglePath,
	Redundant,
}

public readonly record struct ServerStatus(PowerState Power, bool Online, bool BothInletsOneFeed);

/// <summary>
/// Ports and links for a hall, stored as parallel arrays.
///
/// Nothing here is an object per cable: a link is two port indices, and the route,
/// the visual and the length are derived when something asks. That is the same rule
/// the rest of the simulation follows (CLAUDE.md, rule 1) and it is what lets a
/// hundred racks of patching stay cheap.
/// </summary>
public sealed class CablingState
{
	private const int NoLink = -1;

	// devices
	private DeviceKind[] _kind = Array.Empty<DeviceKind>();
	private int[] _rack = Array.Empty<int>();
	private Feed[] _feed = Array.Empty<Feed>();
	private int[] _portStart = Array.Empty<int>();
	private int[] _portCount = Array.Empty<int>();
	private int _deviceCount;

	// ports, flattened across devices
	private LineKind[] _portLine = Array.Empty<LineKind>();
	private int[] _portOwner = Array.Empty<int>();
	private int[] _portLink = Array.Empty<int>();
	private int _portCursor;

	// links
	private int[] _linkA = Array.Empty<int>();
	private int[] _linkB = Array.Empty<int>();
	private bool[] _linkLive = Array.Empty<bool>();
	private int _linkCount;

	public int DeviceCount => _deviceCount;
	public int LinkCount => _linkCount;

	public int AddDevice(DeviceKind kind, int rack, int powerPorts, int networkPorts,
		Feed feed = Feed.None)
	{
		int id = _deviceCount++;
		Grow(ref _kind, _deviceCount);
		Grow(ref _rack, _deviceCount);
		Grow(ref _feed, _deviceCount);
		Grow(ref _portStart, _deviceCount);
		Grow(ref _portCount, _deviceCount);

		_kind[id] = kind;
		_rack[id] = rack;
		_feed[id] = feed;
		_portStart[id] = _portCursor;
		_portCount[id] = powerPorts + networkPorts;

		int total = _portCursor + powerPorts + networkPorts;
		Grow(ref _portLine, total);
		Grow(ref _portOwner, total);
		Grow(ref _portLink, total);
		for (int i = 0; i < powerPorts + networkPorts; i++)
		{
			int p = _portCursor + i;
			_portLine[p] = i < powerPorts ? LineKind.Power : LineKind.Network;
			_portOwner[p] = id;
			_portLink[p] = NoLink;
		}
		_portCursor = total;
		return id;
	}

	public DeviceKind KindOf(int device) => _kind[device];
	public int RackOf(int device) => _rack[device];
	public Feed FeedOf(int device) => _feed[device];
	public int PortOf(int device, int index) => _portStart[device] + index;
	public int PortCountOf(int device) => _portCount[device];
	public LineKind LineOf(int port) => _portLine[port];
	public int OwnerOf(int port) => _portOwner[port];
	public bool IsFree(int port) => _portLink[port] == NoLink;

	public int FindFreePort(int device, LineKind line)
	{
		int start = _portStart[device];
		for (int i = 0; i < _portCount[device]; i++)
		{
			int p = start + i;
			if (_portLine[p] == line && _portLink[p] == NoLink)
			{
				return p;
			}
		}
		return -1;
	}

	public ConnectResult CanConnect(int portA, int portB)
	{
		if (portA < 0 || portB < 0 || portA >= _portCursor || portB >= _portCursor)
		{
			return ConnectResult.UnknownPort;
		}
		if (_portLine[portA] != _portLine[portB])
		{
			return ConnectResult.MixedLineKinds;
		}
		if (_portOwner[portA] == _portOwner[portB])
		{
			return ConnectResult.SameDevice;
		}
		if (_portLink[portA] != NoLink || _portLink[portB] != NoLink)
		{
			return ConnectResult.PortOccupied;
		}
		return WithinReach(_portOwner[portA], _portOwner[portB], _portLine[portA])
			? ConnectResult.Ok
			: ConnectResult.OutOfReach;
	}

	public ConnectResult Connect(int portA, int portB, out int link)
	{
		link = -1;
		ConnectResult check = CanConnect(portA, portB);
		if (check != ConnectResult.Ok)
		{
			return check;
		}

		link = _linkCount++;
		Grow(ref _linkA, _linkCount);
		Grow(ref _linkB, _linkCount);
		Grow(ref _linkLive, _linkCount);
		_linkA[link] = portA;
		_linkB[link] = portB;
		_linkLive[link] = true;
		_portLink[portA] = link;
		_portLink[portB] = link;
		return ConnectResult.Ok;
	}

	public bool Disconnect(int link)
	{
		if (link < 0 || link >= _linkCount || !_linkLive[link])
		{
			return false;
		}
		_portLink[_linkA[link]] = NoLink;
		_portLink[_linkB[link]] = NoLink;
		_linkLive[link] = false;
		return true;
	}

	public bool LinkLive(int link) => link >= 0 && link < _linkCount && _linkLive[link];
	public int LinkPortA(int link) => _linkA[link];
	public int LinkPortB(int link) => _linkB[link];

	/// <summary>Power stays inside its own rack; network may reach a neighbouring one.
	/// Anything further needs a switch in the rack, which is how a player works out
	/// top-of-rack for themselves instead of being told.</summary>
	private bool WithinReach(int deviceA, int deviceB, LineKind line)
	{
		int distance = Math.Abs(_rack[deviceA] - _rack[deviceB]);
		return line == LineKind.Power ? distance == 0 : distance <= 1;
	}

	public ServerStatus StatusOf(int server)
	{
		int start = _portStart[server];
		bool onFeedA = false, onFeedB = false;
		int inlets = 0;
		bool online = false;

		for (int i = 0; i < _portCount[server]; i++)
		{
			int port = start + i;
			int link = _portLink[port];
			if (link == NoLink || !_linkLive[link])
			{
				continue;
			}
			int other = _linkA[link] == port ? _linkB[link] : _linkA[link];
			int otherDevice = _portOwner[other];

			if (_portLine[port] == LineKind.Power)
			{
				inlets++;
				if (_feed[otherDevice] == Feed.A) onFeedA = true;
				if (_feed[otherDevice] == Feed.B) onFeedB = true;
			}
			else if (_kind[otherDevice] is DeviceKind.Switch or DeviceKind.PatchPanel)
			{
				online = true;
			}
		}

		PowerState power = inlets == 0
			? PowerState.Unpowered
			: onFeedA && onFeedB ? PowerState.Redundant : PowerState.SinglePath;
		return new ServerStatus(power, online, inlets >= 2 && !(onFeedA && onFeedB));
	}

	private static void Grow<T>(ref T[] array, int needed)
	{
		if (array.Length >= needed)
		{
			return;
		}
		int size = Math.Max(8, array.Length == 0 ? 8 : array.Length * 2);
		while (size < needed)
		{
			size *= 2;
		}
		Array.Resize(ref array, size);
	}
}
