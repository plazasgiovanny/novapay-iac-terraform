using System.Net;
using System.Text.Json;
using Azure.Messaging.ServiceBus;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using NovaPay.Payments.Data;
using NovaPay.Payments.Models;

namespace NovaPay.Payments.Functions;

/// <summary>
/// HTTP trigger, ruta "confirmations" para que la ruta final del Function App
/// (prefijo por defecto "api") sea /api/confirmations — la misma ruta que
/// Azure API Management reenvia al backend (apim-novapay-{env}, operacion
/// POST /confirmations sobre https://{host}/api).
/// </summary>
public sealed class ValidatePayment
{
    private readonly TransactionalNotificationsRepository _notifications;
    private readonly AccountValidationService _accountValidation;
    private readonly ILogger<ValidatePayment> _logger;

    public ValidatePayment(
        TransactionalNotificationsRepository notifications,
        AccountValidationService accountValidation,
        ILogger<ValidatePayment> logger)
    {
        _notifications = notifications;
        _accountValidation = accountValidation;
        _logger = logger;
    }

    [Function(nameof(ValidatePayment))]
    public async Task<ValidatePaymentResult> RunAsync(
        [HttpTrigger(AuthorizationLevel.Function, "post", Route = "confirmations")] HttpRequestData req,
        CancellationToken cancellationToken)
    {
        PaymentConfirmationRequest? request;
        try
        {
            request = await JsonSerializer.DeserializeAsync<PaymentConfirmationRequest>(
                req.Body, cancellationToken: cancellationToken);
        }
        catch (JsonException)
        {
            return await BadRequestAsync(req, "Body invalido: no se pudo interpretar como JSON.", cancellationToken);
        }

        if (request is null || !request.IsStructurallyValid())
        {
            return await BadRequestAsync(req, "Body invalido: faltan campos requeridos o tienen formato incorrecto.", cancellationToken);
        }

        if (await _notifications.ExistsAsync(request.TransactionId, cancellationToken))
        {
            _logger.LogInformation("TransactionId {TransactionId} ya fue procesado, respondiendo 409.", request.TransactionId);
            var conflict = req.CreateResponse(HttpStatusCode.Conflict);
            await conflict.WriteAsJsonAsync(new { transactionId = request.TransactionId, status = "already_processed" }, cancellationToken);
            return new ValidatePaymentResult(conflict, null);
        }

        var validation = await _accountValidation.ValidateAsync(request, cancellationToken);
        if (!validation.IsValid)
        {
            return await BadRequestAsync(req, validation.Reason!, cancellationToken);
        }

        var paymentEvent = new PaymentValidatedEvent
        {
            TransactionId = request.TransactionId,
            SourceAccount = request.SourceAccount,
            DestinationAccount = request.DestinationAccount,
            Amount = request.Amount,
            Currency = request.Currency,
            Timestamp = DateTimeOffset.UtcNow,
        };

        // MessageId = transactionId: es lo que activa la deduplicacion nativa
        // de Service Bus (ventana configurada en messaging-servicebus/main.tf).
        var message = new ServiceBusMessage(JsonSerializer.SerializeToUtf8Bytes(paymentEvent))
        {
            MessageId = paymentEvent.TransactionId.ToString(),
            ContentType = "application/json",
        };

        _logger.LogInformation("Publicando PaymentValidated para {TransactionId}.", request.TransactionId);

        var accepted = req.CreateResponse(HttpStatusCode.Accepted);
        await accepted.WriteAsJsonAsync(new { transactionId = request.TransactionId, status = "pending" }, cancellationToken);

        return new ValidatePaymentResult(accepted, message);
    }

    private static async Task<ValidatePaymentResult> BadRequestAsync(HttpRequestData req, string reason, CancellationToken cancellationToken)
    {
        var response = req.CreateResponse(HttpStatusCode.BadRequest);
        await response.WriteAsJsonAsync(new { error = reason }, cancellationToken);
        return new ValidatePaymentResult(response, null);
    }
}

/// <summary>
/// Tipo de retorno multi-binding: HTTP (respuesta al cliente, siempre presente)
/// + Service Bus (evento PaymentValidated, solo presente cuando la validacion
/// fue exitosa — en 400/409 el output queda en null y no se publica nada).
/// </summary>
public sealed class ValidatePaymentResult
{
    public ValidatePaymentResult(HttpResponseData httpResponse, ServiceBusMessage? paymentEvent)
    {
        HttpResponse = httpResponse;
        PaymentEvent = paymentEvent;
    }

    public HttpResponseData HttpResponse { get; }

    [ServiceBusOutput("%ServiceBusQueueName%", Connection = "serviceBusConnection")]
    public ServiceBusMessage? PaymentEvent { get; }
}
