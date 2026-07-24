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

    private void Reset_Click(object sender, RoutedEventArgs e)
    {
        _model.ResetDemo();
    }

    private void ShowSection(string section)
    {
        OverviewPanel.Visibility = section == "Overview" ? Visibility.Visible : Visibility.Collapsed;
        FactorsPanel.Visibility = section == "Factors" ? Visibility.Visible : Visibility.Collapsed;
        LabPanel.Visibility = section == "Lab" ? Visibility.Visible : Visibility.Collapsed;
        PrivacyPanel.Visibility = section == "Privacy" ? Visibility.Visible : Visibility.Collapsed;

        foreach (var button in new[] { OverviewNav, FactorsNav, LabNav, PrivacyNav })
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
