namespace Sample.Infrastructure
{
    // Infrastructure-layer type. The architecture rule forbids the Domain layer from depending on it.
    public class Database
    {
        public void Save(string data)
        {
            // Intentionally empty: the fixture only needs a compile-time dependency edge.
        }
    }
}
