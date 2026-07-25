using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

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
        DataPanel.Visibility = section == "Data" ? Visibility.Visible : Visibility.Collapsed;
        SettingsPanel.Visibility = section == "Settings" ? Visibility.Visible : Visibility.Collapsed;
        LogsPanel.Visibility = section == "Logs" ? Visibility.Visible : Visibility.Collapsed;
        PrivacyPanel.Visibility = section == "Privacy" ? Visibility.Visible : Visibility.Collapsed;

        foreach (var button in new[]
                 {
                     OverviewNav,
                     FactorsNav,
                     LabNav,
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
