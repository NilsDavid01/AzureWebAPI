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
