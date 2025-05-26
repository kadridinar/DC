# Define a local cache directory
$CacheDir = "$HOME\pip_cache"
if (!(Test-Path $CacheDir)) { New-Item -ItemType Directory -Path $CacheDir }

# List of package URLs
$Packages = @(
    "https://download.pytorch.org/whl/cpu/torch-2.5.1%2Bcpu-cp39-cp39-win_amd64.whl"
    "https://download.pytorch.org/whl/cpu/torchvision-0.20.1%2Bcpu-cp39-cp39-win_amd64.whl"
    "https://files.pythonhosted.org/packages/37/48/ac2a9584402fb6c0cd5b5d1a91dcf176b15760130dd386bbafdbfe3640bf/numpy-2.2.6-pp310-pypy310_pp73-win_amd64.whl"
    "https://files.pythonhosted.org/packages/84/dd/6abe5d7bd23f5ed3ade8352abf30dff1c7a9e97fc1b0a17b5d7c726e98a9/onnx-1.18.0-cp313-cp313t-win_amd64.whl"
)

# Function to download using BITS (Fully Automated)
Function Download-Package {
    param([string]$url, [string]$dest)

    # Ensure BITS job doesn't duplicate downloads
    $ExistingJob = Get-BitsTransfer | Resume-BitsTransfer | Where-Object { $_.DisplayName -eq $url }
    if ($ExistingJob) {
        Write-Host "BITS job already exists for $url. Resuming..."
        Resume-BitsTransfer -BitsJob $ExistingJob
    } else {
        # Start a new BITS transfer
        Write-Host "Starting BITS Transfer for $url..."
        Start-BitsTransfer -Source $url -Destination $dest -Asynchronous -Description "Downloading $url"
    }
}

# Download packages with BITS resume support
foreach ($url in $Packages) {
    $FileName = Split-Path -Path $url -Leaf
    $DestPath = "$CacheDir\$FileName"
    Download-Package -url $url -dest $DestPath
}

# Monitor BITS transfers and complete automatically
Write-Host "Waiting for downloads to complete... (Showing Progress)"
do {
    $Jobs = Get-BitsTransfer | Where-Object { $_.JobState -eq "Transferring" }

    foreach ($job in $Jobs) {
        if ($job.BytesTotal -gt 0) {
            $percentComplete = ($job.BytesTransferred / $job.BytesTotal) * 100
            Write-Host ("Downloading {0}... {1:N2}% complete" -f $job.DisplayName, $percentComplete)
        } else {
            Write-Host ("Downloading {0}... Waiting for file size data..." -f $job.DisplayName)
        }
    }

    Start-Sleep -Seconds 10
} until ($Jobs.Count -eq 0)

Write-Host "Completing BITS transfers..."
$CompletedJobs = Get-BitsTransfer | Where-Object { $_.JobState -eq "Transferred" }
if ($CompletedJobs) {
    Complete-BitsTransfer -BitsJobId $CompletedJobs.JobId
}

Write-Host "Verifying downloaded files..."
if (!(Get-ChildItem "$CacheDir" -Filter *.whl)) {
    Write-Host "No downloaded packages found! Check BITS transfers."
    Exit
}

Write-Host "Installing packages from cache..."
pip install --no-index --find-links="$CacheDir" -r requirements.txt

Write-Host "All packages installed successfully!"