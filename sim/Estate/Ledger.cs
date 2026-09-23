namespace DataCenter.Sim.Estate;

/// <summary>
/// Money, and the only place it changes.
///
/// A balance that several systems write to is a balance nobody can explain, so every
/// change goes through <see cref="Spend"/> or <see cref="Earn"/> and is counted.
/// Spending more than there is does not throw and does not go negative — it refuses,
/// because "can I afford this" is a question the shop asks constantly and an
/// exception is not an answer.
/// </summary>
public sealed class Ledger
{
	public Ledger(long opening = 0, bool unlimited = false)
	{
		ArgumentOutOfRangeException.ThrowIfNegative(opening);
		Balance = opening;
		Unlimited = unlimited;
	}

	/// <summary>Charges go through and cost nothing. There is no income yet — no
	/// clients, no contracts, no bills — so a real balance only limits how much of the
	/// rest of the game can be reached, which is the opposite of what it is for. It
	/// still counts what was spent, and the screen says plainly that it is off.</summary>
	public bool Unlimited { get; set; }

	public long Balance { get; private set; }
	public long Spent { get; private set; }
	public long Earned { get; private set; }

	public bool CanAfford(long amount) => amount >= 0 && (Unlimited || amount <= Balance);

	public bool Spend(long amount)
	{
		if (!CanAfford(amount))
		{
			return false;
		}
		if (!Unlimited)
		{
			Balance -= amount;
		}
		Spent += amount;
		return true;
	}

	public void Earn(long amount)
	{
		ArgumentOutOfRangeException.ThrowIfNegative(amount);
		Balance += amount;
		Earned += amount;
	}
}
