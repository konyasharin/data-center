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
	public Ledger(long opening = 0)
	{
		ArgumentOutOfRangeException.ThrowIfNegative(opening);
		Balance = opening;
	}

	public long Balance { get; private set; }
	public long Spent { get; private set; }
	public long Earned { get; private set; }

	public bool CanAfford(long amount) => amount >= 0 && amount <= Balance;

	public bool Spend(long amount)
	{
		if (!CanAfford(amount))
		{
			return false;
		}
		Balance -= amount;
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
