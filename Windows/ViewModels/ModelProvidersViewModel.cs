using System.Collections.ObjectModel;

namespace CytisusTrading.Windows;

public sealed record ProviderModelRow(
    ProviderModelRecord Model,
    string Role,
    int FallbackPosition)
{
    public string ModelRecordId => Model.ModelRecordId;
    public string ModelId => Model.ModelId;
    public string DisplayName => Model.DisplayName;
    public bool Enabled => Model.Enabled;
    public string Status => Model.Status.ToString();
    public string Source => Model.Source.ToString();
    public string ToolCalling => Model.SupportsToolCalling.ToString();
}

public sealed class ModelProvidersViewModel : ObservableObject
{
    private readonly ModelProviderManager _manager;
    private ModelProviderProfile? _selectedProvider;
    private ProviderModelRow? _selectedModel;
    private string _providerName = string.Empty;
    private ModelProviderProtocol _protocolType =
        ModelProviderProtocol.OpenAICompatible;
    private string _baseUrl = "https://api.openai.com/v1";
    private string _apiKey = string.Empty;
    private double _requestTimeoutSeconds = 15;
    private bool _confirmRemoteHttp;
    private string _manualModelId = string.Empty;
    private string _modelDisplayName = string.Empty;
    private string _statusMessage =
        "Add a provider or select an existing profile.";
    private string _assistantPrompt = string.Empty;
    private string _assistantResponse =
        "Configure and enable a primary model, then ask a question.";
    private bool _isBusy;
    private bool _editingExisting;

    public ModelProvidersViewModel(ModelProviderManager manager)
    {
        _manager = manager;
        Reload();
    }

    public ObservableCollection<ModelProviderProfile> Providers { get; } = new();
    public ObservableCollection<ProviderModelRow> Models { get; } = new();
    public ObservableCollection<ModelProviderProtocol> ProtocolOptions { get; } =
        new(Enum.GetValues<ModelProviderProtocol>());

    public ModelProviderProfile? SelectedProvider
    {
        get => _selectedProvider;
        set
        {
            if (Set(ref _selectedProvider, value))
            {
                LoadSelectedProvider();
                ReloadModels();
                Raise(nameof(SavedKeyState));
            }
        }
    }

    public ProviderModelRow? SelectedModel
    {
        get => _selectedModel;
        set
        {
            if (Set(ref _selectedModel, value))
            {
                ModelDisplayName = value?.DisplayName ?? string.Empty;
            }
        }
    }

    public string ProviderName
    {
        get => _providerName;
        set => Set(ref _providerName, value);
    }

    public ModelProviderProtocol ProtocolType
    {
        get => _protocolType;
        set => Set(ref _protocolType, value);
    }

    public string BaseUrl
    {
        get => _baseUrl;
        set => Set(ref _baseUrl, value);
    }

    public string ApiKey
    {
        get => _apiKey;
        set => Set(ref _apiKey, value);
    }

    public double RequestTimeoutSeconds
    {
        get => _requestTimeoutSeconds;
        set => Set(ref _requestTimeoutSeconds, value);
    }

    public bool ConfirmRemoteHttp
    {
        get => _confirmRemoteHttp;
        set => Set(ref _confirmRemoteHttp, value);
    }

    public string ManualModelId
    {
        get => _manualModelId;
        set => Set(ref _manualModelId, value);
    }

    public string ModelDisplayName
    {
        get => _modelDisplayName;
        set => Set(ref _modelDisplayName, value);
    }

    public string StatusMessage
    {
        get => _statusMessage;
        private set => Set(ref _statusMessage, value);
    }

    public string AssistantPrompt
    {
        get => _assistantPrompt;
        set => Set(ref _assistantPrompt, value);
    }

    public string AssistantResponse
    {
        get => _assistantResponse;
        private set => Set(ref _assistantResponse, value);
    }

    public bool IsBusy
    {
        get => _isBusy;
        private set => Set(ref _isBusy, value);
    }

    public string SavedKeyState =>
        SelectedProvider is null
            ? "No saved key"
            : "API key saved in Windows CurrentUser protected storage";

    public int SelectedProviderModelCount => SelectedProvider is null
        ? 0
        : _manager.LoadModels().Count(item =>
            item.ProviderId == SelectedProvider.ProviderId);

    public string SelectedProviderRoleBadge
    {
        get
        {
            if (SelectedProvider is null)
            {
                return "None";
            }
            var modelIds = _manager.LoadModels()
                .Where(item => item.ProviderId == SelectedProvider.ProviderId)
                .Select(item => item.ModelRecordId)
                .ToHashSet(StringComparer.Ordinal);
            var roles = _manager.LoadAssignments()
                .Where(item => modelIds.Contains(item.ModelRecordId))
                .Select(item => item.Role.ToString())
                .Distinct(StringComparer.Ordinal)
                .ToArray();
            return roles.Length == 0 ? "None" : string.Join(", ", roles);
        }
    }

    public string SelectionSummary
    {
        get
        {
            var chain = _manager.SelectionChain();
            return chain.Count == 0
                ? "No Ready primary model is selected."
                : string.Join(
                    " -> ",
                    chain.Select(item =>
                        $"{item.Provider.DisplayName}/{item.Model.DisplayName}"));
        }
    }

    public void BeginAdd()
    {
        _editingExisting = false;
        _selectedProvider = null;
        Raise(nameof(SelectedProvider));
        ProviderName = string.Empty;
        ProtocolType = ModelProviderProtocol.OpenAICompatible;
        BaseUrl = "https://api.openai.com/v1";
        ApiKey = string.Empty;
        RequestTimeoutSeconds = 15;
        ConfirmRemoteHttp = false;
        Models.Clear();
        StatusMessage = "Enter provider metadata and an API key.";
        Raise(nameof(SavedKeyState));
    }

    public void BeginEdit()
    {
        if (SelectedProvider is null)
        {
            StatusMessage = "Select a provider to edit.";
            return;
        }
        _editingExisting = true;
        LoadSelectedProvider();
        StatusMessage =
            "Editing disables the provider until it is tested again.";
    }

    public void SaveProvider()
    {
        try
        {
            if (_editingExisting && SelectedProvider is not null)
            {
                _manager.UpdateProvider(
                    SelectedProvider.ProviderId,
                    ProviderName,
                    ProtocolType,
                    BaseUrl,
                    (int)RequestTimeoutSeconds,
                    ConfirmRemoteHttp);
                StatusMessage = "Provider metadata updated.";
            }
            else
            {
                if (string.IsNullOrEmpty(ApiKey))
                {
                    throw new InvalidOperationException(
                        "An API key is required for a new provider.");
                }
                var provider = _manager.AddProvider(
                    ProviderName,
                    ProtocolType,
                    BaseUrl,
                    (int)RequestTimeoutSeconds,
                    ApiKey,
                    ConfirmRemoteHttp);
                StatusMessage = "Provider saved as Not Verified.";
                _editingExisting = true;
                Reload(provider.ProviderId);
            }
            ApiKey = string.Empty;
            Reload(SelectedProvider?.ProviderId);
        }
        catch (Exception exception)
        {
            StatusMessage = SensitiveDataRedactor.Redact(exception.Message);
        }
    }

    public void ReplaceApiKey()
    {
        if (SelectedProvider is null || string.IsNullOrEmpty(ApiKey))
        {
            StatusMessage = "Select a provider and enter a replacement key.";
            return;
        }
        try
        {
            _manager.ReplaceApiKey(SelectedProvider.ProviderId, ApiKey);
            ApiKey = string.Empty;
            StatusMessage = "API key replaced. Test before enabling.";
            Reload(SelectedProvider.ProviderId);
        }
        catch (Exception exception)
        {
            StatusMessage = SensitiveDataRedactor.Redact(exception.Message);
        }
    }

    public void DeleteProvider()
    {
        if (SelectedProvider is null)
        {
            StatusMessage = "Select a provider to delete.";
            return;
        }
        try
        {
            _manager.DeleteProvider(SelectedProvider.ProviderId);
            StatusMessage = "Provider, models, roles, and secure key deleted.";
            Reload();
        }
        catch (Exception exception)
        {
            StatusMessage = SensitiveDataRedactor.Redact(exception.Message);
        }
    }

    public void ToggleProvider()
    {
        if (SelectedProvider is null)
        {
            StatusMessage = "Select a provider.";
            return;
        }
        try
        {
            _manager.SetProviderEnabled(
                SelectedProvider.ProviderId,
                !SelectedProvider.Enabled);
            StatusMessage = SelectedProvider.Enabled
                ? "Provider disabled."
                : "Provider enabled.";
            Reload(SelectedProvider.ProviderId);
        }
        catch (Exception exception)
        {
            StatusMessage = SensitiveDataRedactor.Redact(exception.Message);
        }
    }

    public async Task TestConnectionAsync()
    {
        if (SelectedProvider is null || SelectedModel is null)
        {
            StatusMessage = "Select a provider and model to test.";
            return;
        }
        IsBusy = true;
        try
        {
            var result = await _manager.TestConnectionAsync(
                SelectedProvider.ProviderId,
                SelectedModel.ModelRecordId,
                CancellationToken.None);
            StatusMessage =
                $"{result.Category}: {SensitiveDataRedactor.Redact(result.Message)}";
            Reload(SelectedProvider.ProviderId, SelectedModel.ModelRecordId);
        }
        finally
        {
            IsBusy = false;
        }
    }

    public async Task DiscoverModelsAsync()
    {
        if (SelectedProvider is null)
        {
            StatusMessage = "Select a provider.";
            return;
        }
        IsBusy = true;
        try
        {
            var discovered = await _manager.DiscoverModelsAsync(
                SelectedProvider.ProviderId,
                CancellationToken.None);
            StatusMessage =
                $"Discovered {discovered.Count} models. They remain disabled.";
            Reload(SelectedProvider.ProviderId);
        }
        catch (Exception exception)
        {
            StatusMessage = SensitiveDataRedactor.Redact(exception.Message);
        }
        finally
        {
            IsBusy = false;
        }
    }

    public async Task AskAssistantAsync(bool algorithmProposal)
    {
        var prompt = AssistantPrompt.Trim();
        if (string.IsNullOrWhiteSpace(prompt))
        {
            AssistantResponse = "Enter a question or algorithm-change request.";
            return;
        }

        IsBusy = true;
        try
        {
            var systemInstruction = algorithmProposal
                ? "You are the Cytisus quantitative algorithm reviewer. Return a concise, review-only change proposal with rationale, affected algorithm area, risks, and validation steps. Do not claim that code, settings, files, or orders were changed. Never request secrets."
                : "You are the Cytisus model assistant. Answer concisely. Distinguish network model and Longbridge services from local quantitative CPU/GPU compute. Never request secrets or claim that broker orders were submitted.";
            var outcome = await _manager.GenerateTextWithFallbackAsync(
                systemInstruction,
                prompt,
                CancellationToken.None);
            AssistantResponse = outcome.Text;
            StatusMessage =
                $"Response from {outcome.Selection.Provider.DisplayName}/{outcome.Selection.Model.DisplayName}.";
        }
        catch (Exception exception)
        {
            AssistantResponse =
                SensitiveDataRedactor.Redact(exception.Message);
        }
        finally
        {
            IsBusy = false;
        }
    }

    public void AddManualModel()
    {
        if (SelectedProvider is null)
        {
            StatusMessage = "Select a provider.";
            return;
        }
        try
        {
            var model = _manager.AddManualModel(
                SelectedProvider.ProviderId,
                ManualModelId);
            ManualModelId = string.Empty;
            StatusMessage = "Manual model added as disabled and unverified.";
            Reload(SelectedProvider.ProviderId, model.ModelRecordId);
        }
        catch (Exception exception)
        {
            StatusMessage = SensitiveDataRedactor.Redact(exception.Message);
        }
    }

    public void ToggleModel()
    {
        if (SelectedModel is null)
        {
            StatusMessage = "Select a model.";
            return;
        }
        RunModelAction(() => _manager.SetModelEnabled(
            SelectedModel.ModelRecordId,
            !SelectedModel.Enabled));
    }

    public void UpdateModelDisplayName()
    {
        if (SelectedModel is not null)
        {
            RunModelAction(() => _manager.UpdateModelDisplayName(
                SelectedModel.ModelRecordId,
                ModelDisplayName));
        }
    }

    public void RemoveModel()
    {
        if (SelectedModel is not null)
        {
            var modelId = SelectedModel.ModelRecordId;
            var providerId = SelectedProvider?.ProviderId;
            try
            {
                _manager.RemoveModel(modelId);
                StatusMessage = "Model and its role assignment removed.";
                Reload(providerId);
            }
            catch (Exception exception)
            {
                StatusMessage = SensitiveDataRedactor.Redact(exception.Message);
            }
        }
    }

    public void SetPrimary()
    {
        if (SelectedModel is not null)
        {
            RunModelAction(() => _manager.SetPrimary(
                SelectedModel.ModelRecordId));
        }
    }

    public void AddFallback()
    {
        if (SelectedModel is not null)
        {
            RunModelAction(() => _manager.AddFallback(
                SelectedModel.ModelRecordId));
        }
    }

    public void RemoveRole()
    {
        if (SelectedModel is not null)
        {
            RunModelAction(() => _manager.RemoveRole(
                SelectedModel.ModelRecordId));
        }
    }

    public void MoveFallback(int delta)
    {
        if (SelectedModel is not null)
        {
            RunModelAction(() => _manager.MoveFallback(
                SelectedModel.ModelRecordId,
                delta));
        }
    }

    private void RunModelAction(Action action)
    {
        var providerId = SelectedProvider?.ProviderId;
        var modelId = SelectedModel?.ModelRecordId;
        try
        {
            action();
            StatusMessage = "Model configuration updated.";
            Reload(providerId, modelId);
        }
        catch (Exception exception)
        {
            StatusMessage = SensitiveDataRedactor.Redact(exception.Message);
        }
    }

    private void Reload(string? providerId = null, string? modelId = null)
    {
        var selectedProviderId = providerId ?? SelectedProvider?.ProviderId;
        Providers.Clear();
        foreach (var provider in _manager.LoadProviders())
        {
            Providers.Add(provider);
        }
        SelectedProvider = Providers.FirstOrDefault(item =>
            item.ProviderId == selectedProviderId) ?? Providers.FirstOrDefault();
        ReloadModels(modelId);
        Raise(nameof(SelectionSummary));
        Raise(nameof(SelectedProviderModelCount));
        Raise(nameof(SelectedProviderRoleBadge));
    }

    private void ReloadModels(string? modelId = null)
    {
        var selectedModelId = modelId ?? SelectedModel?.ModelRecordId;
        Models.Clear();
        if (SelectedProvider is null)
        {
            SelectedModel = null;
            return;
        }
        var assignments = _manager.LoadAssignments();
        foreach (var model in _manager.LoadModels().Where(item =>
                     item.ProviderId == SelectedProvider.ProviderId))
        {
            var assignment = assignments.FirstOrDefault(item =>
                item.ModelRecordId == model.ModelRecordId);
            Models.Add(new ProviderModelRow(
                model,
                assignment?.Role.ToString() ?? "None",
                assignment?.Position ?? 0));
        }
        SelectedModel = Models.FirstOrDefault(item =>
            item.ModelRecordId == selectedModelId) ?? Models.FirstOrDefault();
        Raise(nameof(SelectionSummary));
        Raise(nameof(SelectedProviderModelCount));
        Raise(nameof(SelectedProviderRoleBadge));
    }

    private void LoadSelectedProvider()
    {
        if (SelectedProvider is null)
        {
            return;
        }
        _editingExisting = true;
        ProviderName = SelectedProvider.DisplayName;
        ProtocolType = SelectedProvider.ProtocolType;
        BaseUrl = SelectedProvider.BaseUrl;
        RequestTimeoutSeconds = SelectedProvider.RequestTimeoutSeconds;
        ConfirmRemoteHttp = false;
        ApiKey = string.Empty;
    }
}
