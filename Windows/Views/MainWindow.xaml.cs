using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Diagnostics;

namespace CytisusTrading.Windows;

public partial class MainWindow : Window
{
    private readonly StudioViewModel _model = new();

    public MainWindow()
    {
        InitializeComponent();
        DataContext = _model;
        ShowSection("Overview");
    }

    private void NavButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button button && button.Tag is string section)
        {
            ShowSection(section);
        }
    }

    private void RunReview_Click(object sender, RoutedEventArgs e)
    {
        _model.RunReview();
    }

    private void RunFactorSearch_Click(object sender, RoutedEventArgs e)
    {
        _model.RunTinyFactorSearch();
    }

    private void Reset_Click(object sender, RoutedEventArgs e)
    {
        _model.ResetDemo();
    }

    private async void RefreshData_Click(object sender, RoutedEventArgs e)
    {
        await _model.RefreshLongbridgeAsync();
    }

    private async void LongbridgeSignIn_Click(object sender, RoutedEventArgs e)
    {
        await _model.SignInLongbridgeAsync();
    }

    private async void LongbridgeCodeSignIn_Click(object sender, RoutedEventArgs e)
    {
        var code = LongbridgeAuthorizationCodeBox.Password;
        LongbridgeAuthorizationCodeBox.Clear();
        try
        {
            await _model.SignInLongbridgeWithCodeAsync(code);
        }
        finally
        {
            LongbridgeAuthorizationCodeBox.Clear();
        }
    }

    private void LongbridgeCancelSignIn_Click(object sender, RoutedEventArgs e)
    {
        _model.CancelLongbridgeSignIn();
    }

    private async void LongbridgeSignOut_Click(object sender, RoutedEventArgs e)
    {
        var result = MessageBox.Show(
            this,
            "Sign out of Longbridge Terminal on this device?",
            "Sign out",
            MessageBoxButton.OKCancel,
            MessageBoxImage.Warning);
        if (result == MessageBoxResult.OK)
        {
            await _model.SignOutLongbridgeAsync();
        }
    }

    private async void LongbridgeUpdate_Click(object sender, RoutedEventArgs e)
    {
        var result = MessageBox.Show(
            this,
            "Run the allowlisted Longbridge Terminal update command?",
            "Update Longbridge Terminal",
            MessageBoxButton.OKCancel,
            MessageBoxImage.Question);
        if (result == MessageBoxResult.OK)
        {
            await _model.UpdateLongbridgeAsync();
        }
    }

    private void CopyLongbridgeInstall_Click(object sender, RoutedEventArgs e)
    {
        Clipboard.SetText(LongbridgeInstallGuidance.WindowsPowerShell);
    }

    private void OpenLongbridgeRepository_Click(object sender, RoutedEventArgs e)
    {
        OpenUrl(LongbridgeInstallGuidance.RepositoryUrl);
    }

    private void OpenLongbridgeAuthorization_Click(object sender, RoutedEventArgs e)
    {
        OpenUrl(_model.LongbridgeAuthorizationUrl);
    }

    private void CopyLongbridgeShortCode_Click(object sender, RoutedEventArgs e)
    {
        if (!string.IsNullOrWhiteSpace(_model.LongbridgeShortCode))
        {
            Clipboard.SetText(_model.LongbridgeShortCode);
        }
    }

    private static void OpenUrl(string url)
    {
        if (Uri.TryCreate(url, UriKind.Absolute, out var parsed) &&
            parsed.Scheme == Uri.UriSchemeHttps)
        {
            Process.Start(new ProcessStartInfo(parsed.AbsoluteUri)
            {
                UseShellExecute = true
            });
        }
    }

    private void RegisterStrategy_Click(object sender, RoutedEventArgs e)
    {
        _model.RegisterThirdPartyStrategy();
    }

    private async void StartStrategy_Click(object sender, RoutedEventArgs e)
    {
        await _model.StartSelectedStrategyAsync();
    }

    private async void PauseStrategy_Click(object sender, RoutedEventArgs e)
    {
        await _model.PauseSelectedStrategyAsync();
    }

    private async void ResumeStrategy_Click(object sender, RoutedEventArgs e)
    {
        await _model.ResumeSelectedStrategyAsync();
    }

    private async void StopStrategy_Click(object sender, RoutedEventArgs e)
    {
        await _model.StopSelectedStrategyAsync();
    }

    private void RunPaperCycle_Click(object sender, RoutedEventArgs e)
    {
        _model.RunSelectedPaperCycle();
    }

    private void ApplyParameter_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button
            {
                DataContext: StrategyParameterViewModel parameter
            })
        {
            _model.ApplyParameterChange(parameter);
        }
    }

    private void RequestLive_Click(object sender, RoutedEventArgs e)
    {
        _model.RequestLiveMode();
    }

    private void UsePaper_Click(object sender, RoutedEventArgs e)
    {
        _model.RequestPaperMode();
    }

    private void RunReconciliationDiagnostic_Click(
        object sender,
        RoutedEventArgs e)
    {
        _model.RunReconciliationDiagnostic();
    }

    private void ModelApiKeyBox_PasswordChanged(
        object sender,
        RoutedEventArgs e)
    {
        if (sender is PasswordBox passwordBox)
        {
            _model.ModelProviders.ApiKey = passwordBox.Password;
        }
    }

    private void AddProvider_Click(object sender, RoutedEventArgs e)
    {
        ModelApiKeyBox.Clear();
        _model.ModelProviders.BeginAdd();
    }

    private void EditProvider_Click(object sender, RoutedEventArgs e)
    {
        ModelApiKeyBox.Clear();
        _model.ModelProviders.BeginEdit();
    }

    private void SaveProvider_Click(object sender, RoutedEventArgs e)
    {
        _model.ModelProviders.SaveProvider();
        ModelApiKeyBox.Clear();
    }

    private void ReplaceProviderKey_Click(object sender, RoutedEventArgs e)
    {
        _model.ModelProviders.ReplaceApiKey();
        ModelApiKeyBox.Clear();
    }

    private void DeleteProvider_Click(object sender, RoutedEventArgs e)
    {
        if (_model.ModelProviders.SelectedProvider is null)
        {
            return;
        }
        var result = MessageBox.Show(
            this,
            "Delete this provider, its models, role assignments, and protected API key?",
            "Delete provider",
            MessageBoxButton.OKCancel,
            MessageBoxImage.Warning);
        if (result == MessageBoxResult.OK)
        {
            _model.ModelProviders.DeleteProvider();
            ModelApiKeyBox.Clear();
        }
    }

    private void ToggleProvider_Click(object sender, RoutedEventArgs e)
    {
        _model.ModelProviders.ToggleProvider();
    }

    private async void TestProvider_Click(object sender, RoutedEventArgs e)
    {
        await _model.ModelProviders.TestConnectionAsync();
    }

    private async void DiscoverModels_Click(object sender, RoutedEventArgs e)
    {
        await _model.ModelProviders.DiscoverModelsAsync();
    }

    private void AddManualModel_Click(object sender, RoutedEventArgs e)
    {
        _model.ModelProviders.AddManualModel();
    }

    private void ToggleModel_Click(object sender, RoutedEventArgs e)
    {
        _model.ModelProviders.ToggleModel();
    }

    private void UpdateModelDisplayName_Click(
        object sender,
        RoutedEventArgs e)
    {
        _model.ModelProviders.UpdateModelDisplayName();
    }

    private void RemoveModel_Click(object sender, RoutedEventArgs e)
    {
        if (_model.ModelProviders.SelectedModel is null)
        {
            return;
        }
        var result = MessageBox.Show(
            this,
            "Remove this model and its role assignment?",
            "Remove model",
            MessageBoxButton.OKCancel,
            MessageBoxImage.Warning);
        if (result == MessageBoxResult.OK)
        {
            _model.ModelProviders.RemoveModel();
        }
    }

    private void SetPrimaryModel_Click(object sender, RoutedEventArgs e)
    {
        _model.ModelProviders.SetPrimary();
    }

    private void AddFallbackModel_Click(object sender, RoutedEventArgs e)
    {
        _model.ModelProviders.AddFallback();
    }

    private void RemoveModelRole_Click(object sender, RoutedEventArgs e)
    {
        _model.ModelProviders.RemoveRole();
    }

    private void MoveFallbackUp_Click(object sender, RoutedEventArgs e)
    {
        _model.ModelProviders.MoveFallback(-1);
    }

    private void MoveFallbackDown_Click(object sender, RoutedEventArgs e)
    {
        _model.ModelProviders.MoveFallback(1);
    }

    private void StopRiskTransition_Checked(
        object sender,
        RoutedEventArgs e)
    {
        _model.SelectedTransition =
            LiveToPaperTransition.StopOpeningRisk;
    }

    private void FreezeTransition_Checked(
        object sender,
        RoutedEventArgs e)
    {
        _model.SelectedTransition = LiveToPaperTransition.Freeze;
    }

    private void ControlledExitTransition_Checked(
        object sender,
        RoutedEventArgs e)
    {
        _model.SelectedTransition =
            LiveToPaperTransition.ControlledExit;
    }

    private void ShowSection(string section)
    {
        OverviewPanel.Visibility = section == "Overview" ? Visibility.Visible : Visibility.Collapsed;
        FactorsPanel.Visibility = section == "Factors" ? Visibility.Visible : Visibility.Collapsed;
        LabPanel.Visibility = section == "Lab" ? Visibility.Visible : Visibility.Collapsed;
        PortfolioPanel.Visibility = section == "Portfolio" ? Visibility.Visible : Visibility.Collapsed;
        ExecutionPanel.Visibility = section == "Execution" ? Visibility.Visible : Visibility.Collapsed;
        AlgorithmStudioPanel.Visibility = section == "AlgorithmStudio" ? Visibility.Visible : Visibility.Collapsed;
        DataPanel.Visibility = section == "Data" ? Visibility.Visible : Visibility.Collapsed;
        SettingsPanel.Visibility = section == "Settings" ? Visibility.Visible : Visibility.Collapsed;
        LogsPanel.Visibility = section == "Logs" ? Visibility.Visible : Visibility.Collapsed;
        PrivacyPanel.Visibility = section == "Privacy" ? Visibility.Visible : Visibility.Collapsed;

        foreach (var button in new[]
                 {
                     OverviewNav,
                     FactorsNav,
                     LabNav,
                     PortfolioNav,
                     ExecutionNav,
                     AlgorithmStudioNav,
                     DataNav,
                     SettingsNav,
                     LogsNav,
                     PrivacyNav
                 })
        {
            var active = Equals(button.Tag, section);
            button.Background = active
                ? (Brush)FindResource("ActiveNavBrush")
                : Brushes.Transparent;
            button.Foreground = active
                ? (Brush)FindResource("PrimaryTextBrush")
                : (Brush)FindResource("SecondaryTextBrush");
            button.FontWeight = active ? FontWeights.SemiBold : FontWeights.Normal;
        }
    }
}
