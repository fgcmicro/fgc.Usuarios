using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;
using Microsoft.Extensions.Configuration;

namespace Usuarios.Infrastructure.Data;

public class ApplicationDbContextFactory : IDesignTimeDbContextFactory<ApplicationDbContext>
{
    public ApplicationDbContext CreateDbContext(string[] args)
    {
        // Carrega a configuração do projeto API
        var configuration = new ConfigurationBuilder()
            .SetBasePath(Path.Combine(Directory.GetCurrentDirectory(), "../Usuarios.API"))
            .AddJsonFile("appsettings.json", optional: false)
            .AddJsonFile("appsettings.Development.json", optional: true)
            .Build();

        var options = new DbContextOptionsBuilder<ApplicationDbContext>();

        // Detecta o provider baseado na configuração
        var provider = configuration["DatabaseProvider"] ?? "SqlServer";

        Console.WriteLine($"Using {provider} provider");

        var connectionString = configuration.GetConnectionString("Postgres");
        options.UseNpgsql(connectionString, x =>
        {
            x.MigrationsHistoryTable("__EFMigrationsHistory", "public");
        });

        return new ApplicationDbContext(options.Options);
    }
}