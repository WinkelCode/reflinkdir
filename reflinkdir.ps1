$reflinkExe = "$env:LOCALAPPDATA\Programs\.bin\reflink.exe"

if ($args.Count -lt 2 -or $args.Count -gt 3) {
	Write-Output "Too few or too many arguments, make sure folders are properly quoted"
	Write-Output "Usage: $(${MyInvocation}.InvocationName) <source> <target> [dry run delay in ms, implies dry run]"
	exit 1
}

$source = $args[0]
if ($source -notmatch "[\\/]$") { $source += "\" }
$target = $args[1]
if ($target -notmatch "[\\/]$") { $target += "\" }
[System.IO.Directory]::SetCurrentDirectory($PWD)
$source = [IO.Path]::GetFullPath($source)
$target = [IO.Path]::GetFullPath($target)
if (-not (Test-Path $source)) {
	Write-Output "Source directory '$source' does not exist"
	exit 1
} elseif (Test-Path $target) {
	Write-Output "Target path '$target' already exists"
	exit 1
}
Write-Output "Will replicate directory structure and reflink files:`n`tSource (Existing Directory): '$source'`n`tTarget (New Snapshot Directory): '$target'"
if ($args[2]) {
	$dryRun = $true
	$artificalDelay = $args[2]
	if ($artificalDelay -notmatch "^[0-9]+$") {
		Write-Output "Dry run delay must be a positive integer"
		exit 1
	}
	Write-Output "Will dry run with ${artificalDelay}ms delay between each item"
} else {
	$dryRun = $false
	Write-Output "To dry run, pass a third argument (positive integer) to specify the artifical delay in milliseconds between each item"
}
$confirm = Read-Host "Proceed? (y/N)"
if ($confirm -ne "y") {
	Write-Output "Aborting..."
	exit
}

Write-Progress -Activity "Enumerating Items" -Status "Enumerating items in '${source}'..." -PercentComplete -1
$items = Get-ChildItem -Path $source -Recurse -ErrorVariable itemsErr
if ($itemsErr) {
	Write-Output "Not all items could be enumerated due to $(${itemsErr}.Count) errors:"
	foreach ($err in $itemsErr) {
		Write-Output "`t${err}"
	}
	exit 1
}

$itemCount = $items.Count
$itemIndex = 0
$itemsFileCount = $items | Where-Object { $_.PSIsContainer -eq $false } | Measure-Object | Select-Object -ExpandProperty Count
$itemsFileIndex = 0
$itemsDirCount = $items | Where-Object { $_.PSIsContainer -eq $true } | Measure-Object | Select-Object -ExpandProperty Count
$itemsDirIndex = 0
foreach ($item in $items) {
	$itemIndex++
	$percentComplete = $($itemIndex / $itemCount * 100).ToString("0.000")
	$itemSource = $item.FullName
	$itemTarget = $item.FullName.Replace($source, $target)
	if ($item.PSIsContainer) {
		$itemsDirIndex++
		$itemType = "Directory"
		$status = "Creating Directory"
	} else {
		$itemsFileIndex++
		$itemType = "File"
		$status = "  Creating Reflink"
	}
	$counters = "${percentComplete}% | F:${itemsFileIndex}/${itemsFileCount} D:${itemsDirIndex}/${itemsDirCount}"
	Write-Progress -Activity "Cloning Items (${counters})" -Status "${status}: '${itemTarget}'" -PercentComplete $percentComplete
	if ($dryRun) {
		Write-Output "${counters}`t| ${itemType} (Dry Run)`n`tSource: '${itemSource}'`n`tTarget: '${itemTarget}'"
		Start-Sleep -Milliseconds ${artificalDelay} -ErrorVariable err -ErrorAction SilentlyContinue
		continue
	}
	if ($item.PSIsContainer) {
		New-Item -ItemType Directory -Path $itemTarget -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
		if ($err) {
			Write-Output "${counters}`t| Error (Creating Directory)`n`tSource: '${itemSource}'`n`tTarget: '${itemTarget}'`n`tError: '${err}'"
			exit 1
		}
	} else {
		& $reflinkExe $itemSource $itemTarget
		if ($LASTEXITCODE -ne 0) {
			Write-Output "${counters}`t| Error (Creating Reflink)`n`tSource: '${itemSource}'`n`tTarget: '${itemTarget}'`n`tExit Code: '${LASTEXITCODE}'"
			exit 1
		}
	}
}
Write-Output "Done."
