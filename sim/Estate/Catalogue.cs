namespace DataCenter.Sim.Estate;

public enum ItemKind : byte
{
	Server,
	Rack,
}

/// <param name="Units">Rack units the item occupies. A cabinet is measured in the
/// units it offers rather than the ones it takes, which is why a rack reads 42 here
/// and a 1U server reads 1.</param>
public readonly record struct CatalogueItem(
	string Id,
	string Title,
	ItemKind Kind,
	long Price,
	int Units,
	int Watts);

/// <summary>
/// What can be bought, as a table rather than as a set of classes.
///
/// Prices and wattage sit here and nowhere else: the shop reads them, the ledger
/// charges them and the power budget will subtract them, and two of those reading a
/// different number is the bug that is impossible to see on screen.
/// </summary>
public static class Catalogue
{
	private static readonly CatalogueItem[] Items =
	{
		new("server_1u", "Сервер 1U", ItemKind.Server, 2400, 1, 450),
		new("rack_42u", "Шкаф 42U", ItemKind.Rack, 9800, 42, 0),
	};

	public static int Count => Items.Length;

	public static CatalogueItem At(int index)
	{
		ArgumentOutOfRangeException.ThrowIfNegative(index);
		ArgumentOutOfRangeException.ThrowIfGreaterThanOrEqual(index, Items.Length);
		return Items[index];
	}

	public static int IndexOf(string id)
	{
		for (int i = 0; i < Items.Length; i++)
		{
			if (Items[i].Id == id)
			{
				return i;
			}
		}
		return -1;
	}
}
