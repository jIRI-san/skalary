using System.Collections.Generic;
using NetArchTest.Rules;
using Sample.Domain;
using Xunit;

namespace Sample.ArchTests
{
    // Human-owned, reviewed architecture assertions. The runner only ever EXECUTES this reviewed project;
    // it never derives it from contract prose. This is the body a locked contract hashes.
    public class ArchRulesTests
    {
        [Fact]
        public void Domain_should_not_depend_on_Infrastructure()
        {
            var result = Types.InAssembly(typeof(Order).Assembly)
                .That().ResideInNamespace("Sample.Domain")
                .ShouldNot().HaveDependencyOn("Sample.Infrastructure")
                .GetResult();

            // The fixture ships an intentional violation, so this assertion is EXPECTED to fail on a real run,
            // which is exactly what the opt-in adapter eval asserts (status == fail, findings non-empty).
            Assert.True(
                result.IsSuccessful,
                "Domain types must not depend on Infrastructure. Offenders: " +
                string.Join(", ", result.FailingTypeNames ?? new List<string>()));
        }
    }
}
