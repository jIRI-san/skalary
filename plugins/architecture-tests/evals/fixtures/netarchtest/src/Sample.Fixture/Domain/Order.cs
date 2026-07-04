using Sample.Infrastructure;

namespace Sample.Domain
{
    // INTENTIONAL ARCHITECTURE VIOLATION: a Domain type must not depend on the Infrastructure layer,
    // yet Order references Sample.Infrastructure.Database. The NetArchTest rule detects this edge and fails.
    public class Order
    {
        private readonly Database _db = new Database();

        public void Persist()
        {
            _db.Save("order");
        }
    }
}
