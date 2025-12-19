using System.Diagnostics;
using System.Globalization;
using System.Reflection;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;
using Newtonsoft.Json;
using Newtonsoft.Json.Converters;
using Newtonsoft.Json.Serialization;
using Npgsql;
using Prometheus;
using Usuarios.API.Authorization;
using Usuarios.API.Filters;
using Usuarios.API.Logs;
using Usuarios.API.Middlewares;
using Usuarios.Application.Dto;
using Usuarios.Application.Interfaces;
using Usuarios.Application.Services;
using Usuarios.Domain.Configuration;
using Usuarios.Domain.Entities;
using Usuarios.Domain.Enums;
using Usuarios.Domain.Interfaces;
using Usuarios.Domain.Interfaces.Infraestructure;
using Usuarios.Domain.Interfaces.Security;
using Usuarios.Domain.Services;
using Usuarios.Domain.Services.Security;
using Usuarios.Infrastructure.Data;
using Usuarios.Infrastructure.Data.Repositories;
using Usuarios.Infrastructure.Helpers;
using static Usuarios.API.Constants.AppConstants;

var builder = WebApplication.CreateBuilder(args);
// builder.WebHost.UseUrls("http://*:80");
var env = builder.Environment;

// Add services to the container.
builder.Services.AddEndpointsApiExplorer();
var pathBase = Environment.GetEnvironmentVariable("PATH_BASE");

builder.Configuration.AddJsonFile("appsettings.json", optional: true, reloadOnChange: true)
                   .AddJsonFile($"appsettings.{env.EnvironmentName}.json", optional: true, reloadOnChange: true);

var jwtKeyConfig = builder.Configuration["Jwt:Key"];
if (string.IsNullOrEmpty(jwtKeyConfig))
    throw new InvalidOperationException("Jwt:Key configuration is missing or empty.");

builder.Services.Configure<TokenConfiguration>(builder.Configuration.GetSection("Jwt"));

builder.Services.AddAuthentication(o =>
{
    o.DefaultScheme = JwtBearerDefaults.AuthenticationScheme;
    o.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
})
.AddJwtBearer(JwtBearerDefaults.AuthenticationScheme, o =>
{
    o.RequireHttpsMetadata = false;
    o.SaveToken = true;
    o.TokenValidationParameters = new TokenValidationParameters()
    {
        ValidateIssuerSigningKey = true,
        IssuerSigningKey = new SymmetricSecurityKey(Convert.FromBase64String(jwtKeyConfig)),
        RequireExpirationTime = true,
        ValidateIssuer = false,
        ValidateAudience = false,
        ValidateLifetime = true
    };
});

builder.Services.AddAuthorization(options =>
{
    options.AddPolicyWithPermission(Policies.Admin, AccessLevel.Admin)
           .AddPolicyWithPermission(Policies.User, AccessLevel.User)
           .AddPolicyWithPermission(Policies.Guest, AccessLevel.Guest);
}).AddAuthorizationBuilder();

builder.Services.AddControllers(options => options.Filters.Add<UserFilter>()).AddNewtonsoftJson(options =>
{
    var settings = options.SerializerSettings;
    settings.NullValueHandling = NullValueHandling.Ignore;
    settings.FloatFormatHandling = FloatFormatHandling.DefaultValue;
    settings.FloatParseHandling = FloatParseHandling.Double;
    settings.ReferenceLoopHandling = ReferenceLoopHandling.Ignore;
    settings.DateFormatString = "yyyy-MM-ddTHH:mm:ss";
    settings.Culture = new CultureInfo("en-US");
    settings.Converters.Add(new StringEnumConverter());
    settings.ContractResolver = new DefaultContractResolver() { NamingStrategy = new SnakeCaseNamingStrategy() };
});

builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo { Title = "Usuarios API", Version = "v1" });

    var xmlFile = $"{Assembly.GetExecutingAssembly().GetName().Name}.xml";
    var xmlPath = Path.Combine(AppContext.BaseDirectory, xmlFile);
    c.IncludeXmlComments(xmlPath);

    c.CustomSchemaIds(type =>
    {
        var namingStrategy = new SnakeCaseNamingStrategy();
        return namingStrategy.GetPropertyName(type.Name, false);
    });

    c.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Description = "JWT Authorization Header - utilizado com Bearer Authentication. \r\n\r\n Insira 'Bearer' [espaço] e então seu token na caixa abaixo.\r\n\r\nExemplo: (informar sem as aspas): 'Bearer 1234sdfgsdf' ",
        Name = "Authorization",
        In = ParameterLocation.Header,
        Type = SecuritySchemeType.ApiKey,
        Scheme = "Bearer",
        BearerFormat = "JWT"
    });

    c.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        {
            new OpenApiSecurityScheme
            {
                Reference = new OpenApiReference
                {
                    Type = ReferenceType.SecurityScheme,
                    Id = "Bearer"
                }
            },
            Array.Empty<string>()
        }
    });
    
    if (!string.IsNullOrEmpty(pathBase))
    {
        c.AddServer(new OpenApiServer
        {
            Url = pathBase.TrimEnd('/')
        });
    }
});

builder.Services.AddHealthChecks();

builder.Services.AddAutoMapper((sp, cfg) =>
{
    cfg.AllowNullDestinationValues = true;
    cfg.AllowNullCollections = true;
    cfg.ConstructServicesUsing(sp.GetService);
}, Assembly.GetAssembly(typeof(BaseModel)));

builder.Logging.ClearProviders();
builder.Logging.AddProvider(new CustomLoggerProvider(new CustomLoggerProviderConfiguration
{
    LogLevel = LogLevel.Information
}));

builder.Services.AddDbContext<ApplicationDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("PostgreSql")));

builder.Services.AddMemoryCache();

#region Repositories

builder.Services.AddScoped<IUserRepository, UserRepository>();

#endregion

#region Services

builder.Services.AddScoped<IUserService, UserService>();
builder.Services.AddScoped<ITokenService, TokenService>();

#endregion

#region Application Services

builder.Services.AddScoped<IUserApplicationService, UserApplicationService>();
builder.Services.AddScoped<ITokenApplicationService, TokenApplicationService>();

#endregion

#region Authorization

builder.Services.AddSingleton<IAuthorizationHandler, RolesAuthorizationHandler>();

#endregion

#region Filters

builder.Services.AddScoped<IAuthorizationFilter, UserFilter>();
builder.Services.AddScoped(x => new UserData());

#endregion

var app = builder.Build();

app.UseHealthChecks("/health");
app.UseHttpMetrics();
app.MapMetrics();

// Configure the HTTP request pipeline.
//if (app.Environment.IsDevelopment())
//{
//    app.UseSwagger();
//    app.UseSwaggerUI(c => c.SwaggerEndpoint("/swagger/v1/swagger.json", "FCGames API v1"));
//}

app.UseSwagger(c =>
{
    c.RouteTemplate = "swagger/{documentName}/swagger.json";
});

app.UseSwaggerUI(c =>
{
    var swaggerPath = string.IsNullOrEmpty(pathBase) 
        ? "./v1/swagger.json" 
        : $"{pathBase.TrimEnd('/')}/swagger/v1/swagger.json";
    c.SwaggerEndpoint(swaggerPath, "FCGUser API v1");
    c.RoutePrefix = "swagger";
});

using (var scope = app.Services.CreateScope())
{
    var services = scope.ServiceProvider;
    var logger = services.GetRequiredService<ILogger<Program>>();

    try
    {
        var context = services.GetRequiredService<ApplicationDbContext>();

        logger.LogInformation("Iniciando processo de migração do banco de dados...");
        await MigrationHelper.RunMigrationsAsync(context);
        logger.LogInformation("Migrações aplicadas com sucesso!");
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Falha na operação do banco de dados: {Message}", ex.Message);
        Console.WriteLine($"Erro no banco: {ex.Message}");
        Console.WriteLine($"Exceção interna: {ex.InnerException?.Message}");

        if (!app.Environment.IsProduction())
        {
            throw;
        }
    }
}

app.UseMiddleware<ErrorHandlingMiddleware>();

app.UseHttpsRedirection();
app.UseAuthorization();
app.MapControllers();

app.Run();