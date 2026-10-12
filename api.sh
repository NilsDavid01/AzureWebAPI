#!/usr/bin/env bash

set -e

PROJECT_DIR="KeyVaultApi"

# Remove old KeysController if it exists locally
if [ -f "Controllers/KeysController.cs" ]; then
    echo "Removing Controllers/KeysController.cs..."
    rm -f "Controllers/KeysController.cs"
fi

# Remove any generated .pem files
rm -f *.pem

echo "Rebuilding project files for Secret-API-Key only..."
mkdir -p Controllers

# 1. Update KeyVaultApi.csproj (Secret & Swagger dependencies only)
cat << 'EOF' > KeyVaultApi.csproj
<Project Sdk="Microsoft.NET.Sdk.Web">

  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <AllowMissingPrunePackageData>true</AllowMissingPrunePackageData>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Azure.Identity" Version="1.11.4" />
    <PackageReference Include="Azure.Security.KeyVault.Secrets" Version="4.6.0" />
    <PackageReference Include="Swashbuckle.AspNetCore" Version="6.5.0" />
  </ItemGroup>

</Project>
EOF

# 2. Update appsettings.json
cat << 'EOF' > appsettings.json
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning"
    }
  },
  "AllowedHosts": "*",
  "KeyVault": {
    "VaultUri": "https://vault-of-secrets.vault.azure.net/"
  }
}
EOF

# 3. Update Program.cs (SecretClient only)
cat << 'EOF' > Program.cs
using Azure.Identity;
using Azure.Security.KeyVault.Secrets;
using Microsoft.OpenApi.Models;

var builder = WebApplication.CreateBuilder(args);

var vaultUri = builder.Configuration["KeyVault:VaultUri"];
if (string.IsNullOrEmpty(vaultUri))
{
    throw new InvalidOperationException("Key Vault URI is missing from configuration.");
}

// Register SecretClient for Managed Identity
builder.Services.AddSingleton(new SecretClient(
    new Uri(vaultUri),
    new DefaultAzureCredential()
));

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo 
    { 
        Title = "Key Vault Secret API", 
        Version = "v1",
        Description = "Web API retrieving secrets from Azure Key Vault using Managed Identity."
    });
});

var app = builder.Build();

app.UseSwagger();
app.UseSwaggerUI(c =>
{
    c.SwaggerEndpoint("/swagger/v1/swagger.json", "Key Vault Secret API v1");
    c.RoutePrefix = string.Empty;
});

app.UseHttpsRedirection();
app.UseAuthorization();
app.MapControllers();

app.Run();
EOF

# 4. Update Controllers/SecretsController.cs (Targeting Secret-API-Key)
cat << 'EOF' > Controllers/SecretsController.cs
using Azure;
using Azure.Security.KeyVault.Secrets;
using Microsoft.AspNetCore.Mvc;

namespace KeyVaultApi.Controllers;

[ApiController]
[Route("api/[controller]")]
public class SecretsController : ControllerBase
{
    private readonly SecretClient _secretClient;
    private readonly ILogger<SecretsController> _logger;

    public SecretsController(SecretClient secretClient, ILogger<SecretsController> logger)
    {
        _secretClient = secretClient;
        _logger = logger;
    }

    /// <summary>
    /// Retrieves a secret value from Azure Key Vault.
    /// </summary>
    /// <param name="secretName">The name of the secret in Key Vault (defaults to 'Secret-API-Key').</param>
    [HttpGet("{secretName?}")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<IActionResult> GetSecret([FromRoute] string secretName = "Secret-API-Key")
    {
        try
        {
            KeyVaultSecret secret = await _secretClient.GetSecretAsync(secretName);
            return Ok(new 
            { 
                SecretName = secret.Name, 
                Value = secret.Value, 
                CreatedOn = secret.Properties.CreatedOn 
            });
        }
        catch (RequestFailedException ex) when (ex.Status == 404)
        {
            _logger.LogWarning("Secret '{SecretName}' not found in Key Vault.", secretName);
            return NotFound(new { Message = $"Secret '{secretName}' was not found in Azure Key Vault." });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving secret '{SecretName}' from Key Vault.", secretName);
            return StatusCode(500, new { Message = "An error occurred while fetching the secret.", Details = ex.Message });
        }
    }
}
EOF

echo "Cleaned up key dependencies and updated API structure successfully."
echo "Running dotnet clean & dotnet run..."
dotnet clean
dotnet run
