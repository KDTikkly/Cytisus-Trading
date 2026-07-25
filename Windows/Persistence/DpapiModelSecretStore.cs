using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

namespace CytisusTrading.Windows;

public sealed class DpapiModelSecretStore : IModelSecretStore
{
    private readonly string _directory;

    public DpapiModelSecretStore(string? directory = null)
    {
        _directory = directory ?? Path.Combine(
            JsonFilePersistentStore.DefaultRootDirectory(),
            "secrets");
    }

    public void Save(string secret, string reference)
    {
        if (string.IsNullOrEmpty(secret))
        {
            throw new ArgumentException("The API key cannot be empty.", nameof(secret));
        }
        Directory.CreateDirectory(_directory);
        var path = PathFor(reference);
        if (File.Exists(path))
        {
            throw new InvalidOperationException("The secret reference already exists.");
        }
        File.WriteAllBytes(path, Protect(Encoding.UTF8.GetBytes(secret)));
    }

    public void Replace(string secret, string reference)
    {
        if (string.IsNullOrEmpty(secret))
        {
            throw new ArgumentException("The API key cannot be empty.", nameof(secret));
        }
        Directory.CreateDirectory(_directory);
        File.WriteAllBytes(
            PathFor(reference),
            Protect(Encoding.UTF8.GetBytes(secret)));
    }

    public string Retrieve(string reference)
    {
        var path = PathFor(reference);
        if (!File.Exists(path))
        {
            throw new KeyNotFoundException("The secure API key is not available.");
        }
        return Encoding.UTF8.GetString(Unprotect(File.ReadAllBytes(path)));
    }

    public void Delete(string reference)
    {
        var path = PathFor(reference);
        if (File.Exists(path))
        {
            File.Delete(path);
        }
    }

    private string PathFor(string reference)
    {
        var digest = SHA256.HashData(Encoding.UTF8.GetBytes(reference));
        return Path.Combine(_directory, Convert.ToHexString(digest) + ".bin");
    }

    private static byte[] Protect(byte[] plaintext)
    {
        return Transform(plaintext, protect: true);
    }

    private static byte[] Unprotect(byte[] ciphertext)
    {
        return Transform(ciphertext, protect: false);
    }

    private static byte[] Transform(byte[] input, bool protect)
    {
        var inputBlob = new DataBlob();
        var outputBlob = new DataBlob();
        try
        {
            inputBlob.Size = input.Length;
            inputBlob.Data = Marshal.AllocHGlobal(input.Length);
            Marshal.Copy(input, 0, inputBlob.Data, input.Length);
            var succeeded = protect
                ? CryptProtectData(
                    ref inputBlob,
                    null,
                    IntPtr.Zero,
                    IntPtr.Zero,
                    IntPtr.Zero,
                    0,
                    out outputBlob)
                : CryptUnprotectData(
                    ref inputBlob,
                    IntPtr.Zero,
                    IntPtr.Zero,
                    IntPtr.Zero,
                    IntPtr.Zero,
                    0,
                    out outputBlob);
            if (!succeeded)
            {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            var result = new byte[outputBlob.Size];
            Marshal.Copy(outputBlob.Data, result, 0, outputBlob.Size);
            return result;
        }
        finally
        {
            if (inputBlob.Data != IntPtr.Zero)
            {
                Marshal.FreeHGlobal(inputBlob.Data);
            }
            if (outputBlob.Data != IntPtr.Zero)
            {
                LocalFree(outputBlob.Data);
            }
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DataBlob
    {
        public int Size;
        public IntPtr Data;
    }

    [DllImport(
        "crypt32.dll",
        SetLastError = true,
        CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CryptProtectData(
        ref DataBlob input,
        string? description,
        IntPtr optionalEntropy,
        IntPtr reserved,
        IntPtr prompt,
        uint flags,
        out DataBlob output);

    [DllImport(
        "crypt32.dll",
        SetLastError = true,
        CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CryptUnprotectData(
        ref DataBlob input,
        IntPtr description,
        IntPtr optionalEntropy,
        IntPtr reserved,
        IntPtr prompt,
        uint flags,
        out DataBlob output);

    [DllImport("kernel32.dll")]
    private static extern IntPtr LocalFree(IntPtr memory);
}

public sealed class InMemoryModelSecretStore : IModelSecretStore
{
    private readonly Dictionary<string, string> _values = new(StringComparer.Ordinal);

    public void Save(string secret, string reference)
    {
        if (!_values.TryAdd(reference, secret))
        {
            throw new InvalidOperationException("The secret reference already exists.");
        }
    }

    public void Replace(string secret, string reference)
    {
        _values[reference] = secret;
    }

    public string Retrieve(string reference)
    {
        return _values.TryGetValue(reference, out var secret)
            ? secret
            : throw new KeyNotFoundException("The secure API key is not available.");
    }

    public void Delete(string reference)
    {
        _values.Remove(reference);
    }
}
