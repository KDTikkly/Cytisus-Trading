using System.Globalization;
using System.Windows.Data;
using System.Windows.Media;

namespace CytisusTrading.Windows.Views;

public sealed class FactorStateBrushConverter : IValueConverter
{
    public object Convert(
        object value,
        Type targetType,
        object parameter,
        CultureInfo culture)
    {
        var state = value is FactorState factorState ? factorState : FactorState.Retired;
        var background = string.Equals(
            parameter?.ToString(),
            "Background",
            StringComparison.OrdinalIgnoreCase);

        return BrushFrom(background ? BackgroundColor(state) : ForegroundColor(state));
    }

    public object ConvertBack(
        object value,
        Type targetType,
        object parameter,
        CultureInfo culture)
    {
        throw new NotSupportedException();
    }

    private static string ForegroundColor(FactorState state)
    {
        return state switch
        {
            FactorState.Candidate => "#FF55D7F1",
            FactorState.Shadow => "#FFA68BFA",
            FactorState.Active => "#FF54D38A",
            FactorState.Reduced => "#FFF4D35E",
            FactorState.Probation => "#FFF7B955",
            FactorState.Retired => "#FF9AA8BC",
            FactorState.Quarantined => "#FFFF6E80",
            _ => "#FFFFFFFF"
        };
    }

    private static string BackgroundColor(FactorState state)
    {
        return state switch
        {
            FactorState.Candidate => "#2255D7F1",
            FactorState.Shadow => "#22A68BFA",
            FactorState.Active => "#2254D38A",
            FactorState.Reduced => "#22F4D35E",
            FactorState.Probation => "#22F7B955",
            FactorState.Retired => "#229AA8BC",
            FactorState.Quarantined => "#22FF6E80",
            _ => "#00000000"
        };
    }

    private static Brush BrushFrom(string color)
    {
        var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(color));
        brush.Freeze();
        return brush;
    }
}
