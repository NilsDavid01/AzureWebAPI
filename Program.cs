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
