using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Markup;

namespace CytisusTrading.Windows;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        var culture = CultureInfo.GetCultureInfo("en-US");
        CultureInfo.DefaultThreadCurrentCulture = culture;
        CultureInfo.DefaultThreadCurrentUICulture = culture;
        FrameworkElement.LanguageProperty.OverrideMetadata(
            typeof(FrameworkElement),
            new FrameworkPropertyMetadata(XmlLanguage.GetLanguage("en-US")));

        base.OnStartup(e);

        if (e.Args.Length > 0 &&
            string.Equals(e.Args[0], "--foundation-smoke", StringComparison.Ordinal))
        {
            var rootDirectory = e.Args.Length > 1
                ? e.Args[1]
                : Path.Combine(Path.GetTempPath(), $"cytisus-foundation-{Guid.NewGuid():N}");
            ShutdownMode = ShutdownMode.OnExplicitShutdown;
            Shutdown(FoundationSmoke.Run(rootDirectory));
            return;
        }

        if (e.Args.Length > 0 &&
            string.Equals(e.Args[0], "--prompt2-smoke", StringComparison.Ordinal))
        {
            var rootDirectory = e.Args.Length > 1
                ? e.Args[1]
                : Path.Combine(Path.GetTempPath(), $"cytisus-prompt2-{Guid.NewGuid():N}");
            ShutdownMode = ShutdownMode.OnExplicitShutdown;
            Shutdown(Prompt2Smoke.Run(rootDirectory));
            return;
        }

        if (e.Args.Length > 0 &&
            string.Equals(e.Args[0], "--prompt3-smoke", StringComparison.Ordinal))
        {
            var rootDirectory = e.Args.Length > 1
                ? e.Args[1]
                : Path.Combine(Path.GetTempPath(), $"cytisus-prompt3-{Guid.NewGuid():N}");
            ShutdownMode = ShutdownMode.OnExplicitShutdown;
            Shutdown(Prompt3Smoke.Run(rootDirectory));
            return;
        }

        if (e.Args.Length > 0 &&
            string.Equals(e.Args[0], "--prompt4-smoke", StringComparison.Ordinal))
        {
            var rootDirectory = e.Args.Length > 1
                ? e.Args[1]
                : Path.Combine(Path.GetTempPath(), $"cytisus-prompt4-{Guid.NewGuid():N}");
            ShutdownMode = ShutdownMode.OnExplicitShutdown;
            Shutdown(Prompt4Smoke.Run(rootDirectory));
            return;
        }

        var window = new MainWindow();
        MainWindow = window;
        window.Show();
    }
}
