# NodaTime SQL Server conventions

Use this alternative when the same domain-time mapping applies model-wide. Keep
the BCL conversion at the provider boundary and verify the generated `date` and
`datetime2` columns.

```csharp
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;
using NodaTime;

public sealed class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    protected override void ConfigureConventions(ModelConfigurationBuilder builder)
    {
        builder.Properties<LocalDate>()
            .HaveConversion<LocalDateToDateTimeConverter>()
            .HaveColumnType("date");
        builder.Properties<Instant>()
            .HaveConversion<InstantToDateTimeConverter>()
            .HaveColumnType("datetime2");
    }
}

public sealed class LocalDateToDateTimeConverter : ValueConverter<LocalDate, DateTime>
{
    public LocalDateToDateTimeConverter() : base(
        value => value.ToDateTimeUnspecified(),
        value => LocalDate.FromDateTime(value)) { }
}

public sealed class InstantToDateTimeConverter : ValueConverter<Instant, DateTime>
{
    public InstantToDateTimeConverter() : base(
        value => value.ToDateTimeUtc(),
        value => Instant.FromDateTimeUtc(DateTime.SpecifyKind(value, DateTimeKind.Utc))) { }
}
```
