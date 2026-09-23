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
/// feed runs fine until that feed is worked on, which is the whole point.
///
/// <c>None</c> is deliberately zero: zeroed memory — a freshly grown array, a
/// half-read save — must not read as "hangs off feed A", or a maintenance sweep
/// would take down devices that were never on that feed.</summary>
public enum Feed : byte
{
	None,
	A,
	B,
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
	PowerNeedsPdu,
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
	private int[] _portRows = Array.Empty<int>();
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

	/// <summary>Ports actually handed out. The arrays behind them grow in powers of
	/// two, so their Length is not the count and a serializer that writes the whole
	/// array writes garbage.</summary>
	public int PortTotal => _portCursor;

	/// <param name="rows">How many rows the ports are laid out in. A switch's
	/// twenty-four sockets are two rows of twelve, and which port sits above which is
	/// not something a caller can work out from the count — it is a fact about the
	/// hardware, and patching reads as tidy or not depending on it.</param>
	public int AddDevice(DeviceKind kind, int rack, int powerPorts, int networkPorts,
		Feed feed = Feed.None, int rows = 1)
	{
		ArgumentOutOfRangeException.ThrowIfNegative(powerPorts);
		ArgumentOutOfRangeException.ThrowIfNegative(networkPorts);

		int id = _deviceCount++;
		Grow(ref _kind, _deviceCount);
		Grow(ref _rack, _deviceCount);
		Grow(ref _feed, _deviceCount);
		Grow(ref _portStart, _deviceCount);
		Grow(ref _portCount, _deviceCount);
		Grow(ref _portRows, _deviceCount);

		_kind[id] = kind;
		_rack[id] = rack;
		_feed[id] = feed;
		_portStart[id] = _portCursor;
		_portCount[id] = powerPorts + networkPorts;
		_portRows[id] = rows < 1 ? 1 : rows;

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

	// The arrays outlive the counts, so the getters below check against the count and
	// not against Length. A stale id would otherwise read as a real device standing in
	// rack 0 — an existing rack — and quietly join whatever sweep is running.
	public DeviceKind KindOf(int device) => _kind[Device(device)];
	public int RackOf(int device) => _rack[Device(device)];
	public Feed FeedOf(int device) => _feed[Device(device)];
	public int PortCountOf(int device) => _portCount[Device(device)];
	public int RowsOf(int device) => _portRows[Device(device)];

	/// <summary>Which cabinet a device stands in, after it has been carried to another
	/// one. The rack is the only thing about a device that is not fixed when it is
	/// made: reach is measured between racks, so a chassis that moved and did not say
	/// so can be patched to somewhere it cannot physically reach.</summary>
	public void MoveDevice(int device, int rack)
	{
		_rack[Device(device)] = rack;
	}
	public LineKind LineOf(int port) => _portLine[Port(port)];
	public int OwnerOf(int port) => _portOwner[Port(port)];
	public bool IsFree(int port) => _portLink[Port(port)] == NoLink;

	/// <summary>The link occupying a port, or -1. What the player grabs when they pull
	/// a cable out of a socket rather than trace it from the far end, and what lets a
	/// bulk disconnect cost the ports it touches instead of every link in the hall.
	/// </summary>
	public int LinkOf(int port) => _portLink[Port(port)];

	public int PortOf(int device, int index)
	{
		Device(device);
		if (index < 0 || index >= _portCount[device])
		{
			throw new ArgumentOutOfRangeException(nameof(index));
		}
		return _portStart[device] + index;
	}

	public int FindFreePort(int device, LineKind line)
	{
		int start = _portStart[Device(device)];
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
		// FindFreePort hands back -1, and "the rack is full" is a different sentence
		// from "that index is nonsense" — the UI has to be able to say which.
		if (portA == -1 || portB == -1)
		{
			return ConnectResult.NoFreePort;
		}
		if (portA < 0 || portB < 0 || portA >= _portCursor || portB >= _portCursor)
		{
			return ConnectResult.UnknownPort;
		}
		if (_portLine[portA] != _portLine[portB])
		{
			return ConnectResult.MixedLineKinds;
		}
		int deviceA = _portOwner[portA], deviceB = _portOwner[portB];
		if (deviceA == deviceB)
		{
			return ConnectResult.SameDevice;
		}
		if (_portLink[portA] != NoLink || _portLink[portB] != NoLink)
		{
			return ConnectResult.PortOccupied;
		}
		// Power has to come from a PDU. Without this, a server patched into the server
		// beside it passes every other check and both of them then report being fed,
		// while neither is on a supply.
		if (_portLine[portA] == LineKind.Power
			&& (_kind[deviceA] == DeviceKind.Pdu) == (_kind[deviceB] == DeviceKind.Pdu))
		{
			return ConnectResult.PowerNeedsPdu;
		}
		return WithinReach(deviceA, deviceB, _portLine[portA])
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
	public int LinkPortA(int link) => LinkLive(link) ? _linkA[link] : -1;
	public int LinkPortB(int link) => LinkLive(link) ? _linkB[link] : -1;

	/// <summary>The far end of whatever is plugged into this port, or -1.</summary>
	public int OtherEnd(int port)
	{
		int link = _portLink[Port(port)];
		return link == NoLink ? -1 : _linkA[link] == port ? _linkB[link] : _linkA[link];
	}

	/// <summary>Takes a whole supply path down, which is what a maintenance window
	/// does. Walked from the PDUs, so it costs the outlets on that feed rather than
	/// every link in the hall.</summary>
	public int DisconnectFeed(Feed feed)
	{
		int pulled = 0;
		for (int device = 0; device < _deviceCount; device++)
		{
			if (_kind[device] != DeviceKind.Pdu || _feed[device] != feed)
			{
				continue;
			}
			int start = _portStart[device];
			for (int i = 0; i < _portCount[device]; i++)
			{
				if (Disconnect(_portLink[start + i]))
				{
					pulled++;
				}
			}
		}
		return pulled;
	}

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
		int start = _portStart[Device(server)];
		bool onFeedA = false, onFeedB = false;
		int inlets = 0;
		bool online = false;

		for (int i = 0; i < _portCount[server]; i++)
		{
			int port = start + i;
			int link = _portLink[port];
			if (link == NoLink)
			{
				continue;
			}
			int other = _linkA[link] == port ? _linkB[link] : _linkA[link];
			int otherDevice = _portOwner[other];

			if (_portLine[port] == LineKind.Power)
			{
				if (_kind[otherDevice] != DeviceKind.Pdu)
				{
					continue;
				}
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
		// Two inlets on one *known* feed. Two inlets into a PDU that is itself on no
		// feed is a different mistake, and calling it this one would send the player
		// looking at the wrong thing.
		return new ServerStatus(power, online, inlets >= 2 && (onFeedA ^ onFeedB));
	}

	private int Device(int device)
	{
		if (device < 0 || device >= _deviceCount)
		{
			throw new ArgumentOutOfRangeException(nameof(device));
		}
		return device;
	}

	private int Port(int port)
	{
		if (port < 0 || port >= _portCursor)
		{
			throw new ArgumentOutOfRangeException(nameof(port));
		}
		return port;
	}

	private static void Grow<T>(ref T[] array, int needed)
	{
		if (array.Length >= needed)
		{
			return;
		}
		int size = Math.Max(8, array.Length * 2);
		while (size < needed)
		{
			size *= 2;
		}
		Array.Resize(ref array, size);
	}
}
