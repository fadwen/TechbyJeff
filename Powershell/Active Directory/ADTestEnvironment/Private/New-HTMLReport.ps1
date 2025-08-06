function New-HTMLReport {
    [CmdletBinding()]
    [OutputType([void])]
    <#
    .SYNOPSIS
        Generates an HTML report from AD test data

    .DESCRIPTION
        Creates a comprehensive HTML report with styling and formatted tables
        from the provided test data structure.

    .PARAMETER ReportData
        The report data hashtable containing all collected AD test information

    .PARAMETER OutputPath
        Path where the HTML file should be saved

    .EXAMPLE
        New-HTMLReport -ReportData $data -OutputPath "C:\Reports\test.html"

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2025-08-03

        Creates a comprehensive HTML report with all available details including:
        - Full object attributes for all AD objects
        - Group membership information
        - Always displays the most detailed information available
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$ReportData,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    begin {
        Write-Verbose "Starting HTML report generation"

        # Ensure output directory exists
        $directory = Split-Path $OutputPath -Parent
        if ($directory -and -not (Test-Path $directory)) {
            try {
                New-Item -Path $directory -ItemType Directory -Force | Out-Null
            }
            catch {
                throw "Cannot create output directory: $directory"
            }
        }
    }

    process {
        try {
            Write-ADTestProgress -Message "Generating HTML report: $OutputPath" -Type Info

            # Build HTML content
            $htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>AD Test Data Report</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        /* Reset and base styles */
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 20px;
            background-color: #f5f5f5;
            line-height: 1.6;
        }

        .container {
            max-width: 1400px;
            margin: 0 auto;
            background-color: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }

        /* Header styles */
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px;
            border-radius: 8px;
            margin-bottom: 20px;
        }
        .header h1 {
            margin: 0 0 10px 0;
            font-size: 2.2em;
        }
        .header p {
            margin: 5px 0;
            opacity: 0.9;
        }

        /* Summary styles */
        .summary {
            background: linear-gradient(135deg, #a8edea 0%, #fed6e3 100%);
            padding: 20px;
            margin: 20px 0;
            border-radius: 8px;
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
        }
        .summary-item {
            background: rgba(255,255,255,0.8);
            padding: 15px;
            border-radius: 6px;
            text-align: center;
        }
        .summary-item .label {
            font-size: 0.9em;
            color: #666;
            margin-bottom: 5px;
        }
        .summary-item .count {
            font-size: 2em;
            font-weight: bold;
            color: #2e7d32;
        }

        /* Collapsible section styles */
        .section {
            margin: 20px 0;
            border-radius: 8px;
            background: #fafafa;
            border: 1px solid #e0e0e0;
            overflow: hidden;
        }

        .section-header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 15px 20px;
            cursor: pointer;
            display: flex;
            justify-content: space-between;
            align-items: center;
            transition: background-color 0.3s ease;
            user-select: none;
        }

        .section-header:hover {
            background: linear-gradient(135deg, #5a6fd8 0%, #6a4190 100%);
        }

        .section-header h2 {
            margin: 0;
            font-size: 1.4em;
        }

        .section-toggle {
            font-size: 1.2em;
            font-weight: bold;
            transition: transform 0.3s ease;
        }

        .section-content {
            display: none;
            padding: 0;
            background: white;
        }

        .section-content.expanded {
            display: block;
        }

        .section.expanded .section-toggle {
            /* Remove the rotation transform since we're using text change instead */
        }

        /* Table container with horizontal scroll */
        .table-container {
            overflow-x: auto;
            margin: 0;
            border-radius: 0;
        }

        /* Table styles */
        table {
            border-collapse: collapse;
            width: 100%;
            min-width: 800px; /* Ensure minimum width for horizontal scroll */
            margin: 0;
            background: white;
        }

        th, td {
            border: 1px solid #e0e0e0;
            padding: 12px 16px;
            text-align: left;
            white-space: nowrap; /* Prevent text wrapping */
        }

        th {
            background: linear-gradient(135deg, #f8f9fa 0%, #e9ecef 100%);
            font-weight: 600;
            color: #495057;
            position: sticky;
            top: 0;
            z-index: 10;
        }

        tr:nth-child(even) {
            background-color: #f8f9fa;
        }

        tr:hover {
            background-color: #e3f2fd;
        }

        /* Nested table styles for group members */
        .group-members-row {
            background-color: #f0f8ff !important;
        }

        .nested-table-container {
            padding: 10px 20px;
            background-color: #f8f9fa;
            border-radius: 4px;
            margin: 5px 0;
        }

        .nested-table {
            width: 100%;
            min-width: auto; /* Override parent table min-width */
            border: 1px solid #d0d0d0;
            border-radius: 4px;
            overflow: hidden;
            background: white;
        }

        .nested-table th {
            background: linear-gradient(135deg, #e8f4f8 0%, #d4e4ef 100%);
            color: #2c5282;
            font-size: 0.9em;
            padding: 8px 12px;
        }

        .nested-table td {
            padding: 8px 12px;
            border-bottom: 1px solid #e8e8e8;
            font-size: 0.9em;
        }

        .nested-table tr:last-child td {
            border-bottom: none;
        }

        .nested-table tr:nth-child(even) {
            background-color: #f9f9f9;
        }

        .nested-table tr:hover {
            background-color: #e6f3ff;
        }

        .group-toggle {
            user-select: none;
            display: inline-block;
            min-width: 20px;
        }

        .group-toggle:hover {
            background-color: rgba(0, 123, 186, 0.1);
            border-radius: 3px;
        }

        /* Status styles */
        .enabled {
            color: #2e7d32;
            font-weight: bold;
        }

        .disabled {
            color: #d32f2f;
            font-weight: bold;
        }

        /* Footer styles */
        .footer {
            text-align: center;
            padding: 20px;
            color: #666;
            font-size: 0.9em;
            border-top: 1px solid #eee;
            margin-top: 40px;
        }

        /* Responsive design */
        @media (max-width: 768px) {
            .container {
                margin: 10px;
                padding: 15px;
            }

            .header h1 {
                font-size: 1.8em;
            }

            .summary {
                grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
                gap: 10px;
            }
        }
    </style>
    <script>
        function toggleSection(sectionId) {
            const section = document.getElementById(sectionId);
            const content = section.querySelector('.section-content');
            const toggle = section.querySelector('.section-toggle');

            if (content.classList.contains('expanded')) {
                content.classList.remove('expanded');
                section.classList.remove('expanded');
                toggle.textContent = '[+]';
            } else {
                content.classList.add('expanded');
                section.classList.add('expanded');
                toggle.textContent = '[-]';
            }
        }

        function expandAll() {
            const sections = document.querySelectorAll('.section');
            sections.forEach(section => {
                const content = section.querySelector('.section-content');
                const toggle = section.querySelector('.section-toggle');
                content.classList.add('expanded');
                section.classList.add('expanded');
                toggle.textContent = '[-]';
            });
        }

        function collapseAll() {
            const sections = document.querySelectorAll('.section');
            sections.forEach(section => {
                const content = section.querySelector('.section-content');
                const toggle = section.querySelector('.section-toggle');
                content.classList.remove('expanded');
                section.classList.remove('expanded');
                toggle.textContent = '[+]';
            });
        }

        function toggleGroupMembers(groupId) {
            const memberRow = document.getElementById('members-' + groupId);
            const toggle = document.getElementById('toggle-' + groupId);

            if (memberRow.style.display === 'none' || memberRow.style.display === '') {
                memberRow.style.display = 'table-row';
                toggle.textContent = '-';
            } else {
                memberRow.style.display = 'none';
                toggle.textContent = '+';
            }
        }

        // Initialize on page load
        document.addEventListener('DOMContentLoaded', function() {
            // All sections start collapsed by default
        });
    </script>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Active Directory Test Data Report</h1>
            <p><strong>Domain:</strong> $($ReportData.Domain)</p>
            <p><strong>Generated:</strong> $($ReportData.GeneratedOn)</p>
            <p><strong>Report ID:</strong> $($ReportData.CorrelationId)</p>
        </div>

        <div class="summary">
            <div class="summary-item">
                <div class="label">Organizational Units</div>
                <div class="count">$($ReportData.Summary.TotalOUs)</div>
            </div>
            <div class="summary-item">
                <div class="label">Users</div>
                <div class="count">$($ReportData.Summary.TotalUsers)</div>
            </div>
            <div class="summary-item">
                <div class="label">Service Accounts</div>
                <div class="count">$($ReportData.Summary.TotalServiceAccounts)</div>
            </div>
            <div class="summary-item">
                <div class="label">Devices</div>
                <div class="count">$($ReportData.Summary.TotalDevices)</div>
            </div>
            <div class="summary-item">
                <div class="label">Groups</div>
                <div class="count">$($ReportData.Summary.TotalGroups)</div>
            </div>
            <div class="summary-item">
                <div class="label">Group Members</div>
                <div class="count">$($ReportData.Summary.TotalGroupMembers)</div>
            </div>
"@

            $htmlContent += "        </div>`n"

            # Add Expand/Collapse buttons after summary but before tables
            $htmlContent += @"
        <div style="text-align: center; margin: 20px 0; padding: 15px; background: #f8f9fa; border-radius: 8px;">
            <button onclick="expandAll()" style="background: #667eea; color: white; border: none; padding: 10px 15px; margin: 5px; border-radius: 4px; cursor: pointer; font-weight: bold;">Expand All</button>
            <button onclick="collapseAll()" style="background: #6c757d; color: white; border: none; padding: 10px 15px; margin: 5px; border-radius: 4px; cursor: pointer; font-weight: bold;">Collapse All</button>
        </div>
"@

            # Show detailed sections (this is what users expect to see) - all collapsible
            if ($ReportData.TestOUs.Count -gt 0) {
                $htmlContent += @"
        <div class="section" id="ous-section">
            <div class="section-header" onclick="toggleSection('ous-section')">
                <h2>Organizational Units ($($ReportData.TestOUs.Count))</h2>
                <span class="section-toggle">[+]</span>
            </div>
            <div class="section-content">
                <div class="table-container">
                    <table>
                        <tr><th>Name</th><th>Description</th><th>Protected from Deletion</th><th>Distinguished Name</th></tr>
"@
                foreach ($ou in $ReportData.TestOUs) {
                    $protected = if ($ou.ProtectedFromAccidentalDeletion) { "Yes" } else { "No" }
                    $htmlContent += "                        <tr><td>$($ou.Name)</td><td>$($ou.Description)</td><td>$protected</td><td>$($ou.DistinguishedName)</td></tr>`n"
                }
                $htmlContent += "                    </table>`n                </div>`n            </div>`n        </div>`n"
            }

            if ($ReportData.TestUsers.Count -gt 0) {
                $htmlContent += @"
        <div class="section" id="users-section">
            <div class="section-header" onclick="toggleSection('users-section')">
                <h2>Test Users ($($ReportData.TestUsers.Count))</h2>
                <span class="section-toggle">[+]</span>
            </div>
            <div class="section-content">
                <div class="table-container">
                    <table>
"@

                # Get a reasonable set of key properties for users instead of all properties
                $userProps = @('Name', 'SamAccountName', 'UserPrincipalName', 'EmailAddress', 'Title', 'Department', 'Manager', 'Enabled', 'DistinguishedName', 'Description')

                # Filter to only properties that exist in the data
                $actualUserProps = @()
                $firstUser = $ReportData.TestUsers | Select-Object -First 1
                foreach ($prop in $userProps) {
                    if ($firstUser.PSObject.Properties.Name -contains $prop) {
                        $actualUserProps += $prop
                    }
                }

                # Add headers
                $htmlContent += "                        <tr>"
                foreach ($prop in $actualUserProps) {
                    $htmlContent += "<th>$prop</th>"
                }
                $htmlContent += "</tr>`n"

                # Add all users with selected properties
                foreach ($user in $ReportData.TestUsers) {
                    $htmlContent += "                        <tr>"
                    foreach ($prop in $actualUserProps) {
                        $value = $user.$prop
                        if ($null -eq $value -or $value -eq "") { $value = "&nbsp;" }
                        $htmlContent += "<td>$value</td>"
                    }
                    $htmlContent += "</tr>`n"
                }
                $htmlContent += "                    </table>`n                </div>`n            </div>`n        </div>`n"
            }

            if ($ReportData.TestServiceAccounts.Count -gt 0) {
                $htmlContent += @"
        <div class="section" id="service-accounts-section">
            <div class="section-header" onclick="toggleSection('service-accounts-section')">
                <h2>Service Accounts ($($ReportData.TestServiceAccounts.Count))</h2>
                <span class="section-toggle">[+]</span>
            </div>
            <div class="section-content">
                <div class="table-container">
                    <table>
"@

                # Get key properties for service accounts
                $serviceAccountProps = @('Name', 'SamAccountName', 'UserPrincipalName', 'Description', 'Manager', 'Enabled', 'DistinguishedName', 'ServicePrincipalNames')

                # Filter to only properties that exist in the data
                $actualServiceAccountProps = @()
                $firstServiceAccount = $ReportData.TestServiceAccounts | Select-Object -First 1
                foreach ($prop in $serviceAccountProps) {
                    if ($firstServiceAccount.PSObject.Properties.Name -contains $prop) {
                        $actualServiceAccountProps += $prop
                    }
                }

                # Add headers
                $htmlContent += "                        <tr>"
                foreach ($prop in $actualServiceAccountProps) {
                    $htmlContent += "<th>$prop</th>"
                }
                $htmlContent += "</tr>`n"

                # Add all service accounts with selected properties
                foreach ($serviceAccount in $ReportData.TestServiceAccounts) {
                    $htmlContent += "                        <tr>"
                    foreach ($prop in $actualServiceAccountProps) {
                        $value = $serviceAccount.$prop
                        if ($null -eq $value -or $value -eq "") { $value = "&nbsp;" }
                        # Handle arrays (like ServicePrincipalNames)
                        if ($value -is [array]) { $value = $value -join ", " }
                        $htmlContent += "<td>$value</td>"
                    }
                    $htmlContent += "</tr>`n"
                }
                $htmlContent += "                    </table>`n                </div>`n            </div>`n        </div>`n"
            }

            if ($ReportData.TestDevices.Count -gt 0) {
                $htmlContent += @"
        <div class="section" id="devices-section">
            <div class="section-header" onclick="toggleSection('devices-section')">
                <h2>Test Devices ($($ReportData.TestDevices.Count))</h2>
                <span class="section-toggle">[+]</span>
            </div>
            <div class="section-content">
                <div class="table-container">
                    <table>
"@

                # Get key properties for devices
                $deviceProps = @('Name', 'SamAccountName', 'DNSHostName', 'OperatingSystem', 'OperatingSystemVersion', 'Description', 'Enabled', 'DistinguishedName')

                # Filter to only properties that exist in the data
                $actualDeviceProps = @()
                $firstDevice = $ReportData.TestDevices | Select-Object -First 1
                foreach ($prop in $deviceProps) {
                    if ($firstDevice.PSObject.Properties.Name -contains $prop) {
                        $actualDeviceProps += $prop
                    }
                }

                # Add headers
                $htmlContent += "                        <tr>"
                foreach ($prop in $actualDeviceProps) {
                    $htmlContent += "<th>$prop</th>"
                }
                $htmlContent += "</tr>`n"

                # Add all devices with selected properties
                foreach ($device in $ReportData.TestDevices) {
                    $htmlContent += "                        <tr>"
                    foreach ($prop in $actualDeviceProps) {
                        $value = $device.$prop
                        if ($null -eq $value -or $value -eq "") { $value = "&nbsp;" }
                        $htmlContent += "<td>$value</td>"
                    }
                    $htmlContent += "</tr>`n"
                }
                $htmlContent += "                    </table>`n                </div>`n            </div>`n        </div>`n"

            if ($ReportData.TestGroups.Count -gt 0) {
                $htmlContent += @"
        <div class="section" id="groups-section">
            <div class="section-header" onclick="toggleSection('groups-section')">
                <h2>Security Groups ($($ReportData.TestGroups.Count))</h2>
                <span class="section-toggle">[+]</span>
            </div>
            <div class="section-content">
                <div class="table-container">
                    <table>
                        <tr>
                            <th>Action</th>
                            <th>Name</th>
                            <th>SamAccountName</th>
                            <th>GroupCategory</th>
                            <th>GroupScope</th>
                            <th>Description</th>
                            <th>Member Count</th>
                            <th>DistinguishedName</th>
                        </tr>
"@

                # Add all groups with member expansion functionality
                foreach ($group in $ReportData.TestGroups) {
                    $groupId = $group.SamAccountName -replace '[^a-zA-Z0-9]', ''  # Safe ID for HTML
                    $memberCount = if ($group.MemberCount) { $group.MemberCount } else { 0 }

                    $htmlContent += @"
                        <tr>
                            <td>
                                <span class="group-toggle" onclick="toggleGroupMembers('$groupId')" style="cursor: pointer; color: #007cba; font-weight: bold;">
                                    [<span id="toggle-$groupId">+</span>]
                                </span>
                            </td>
                            <td>$($group.Name)</td>
                            <td>$($group.SamAccountName)</td>
                            <td>$($group.GroupCategory)</td>
                            <td>$($group.GroupScope)</td>
                            <td>$($group.Description)</td>
                            <td>$memberCount</td>
                            <td>$($group.DistinguishedName)</td>
                        </tr>
"@

                    # Add nested member table row (initially hidden)
                    if ($group.Members -and $group.Members.Count -gt 0) {
                        $htmlContent += @"
                        <tr id="members-$groupId" class="group-members-row" style="display: none;">
                            <td colspan="8">
                                <div class="nested-table-container">
                                    <table class="nested-table">
                                        <tr>
                                            <th>Member Name</th>
                                            <th>Member Type</th>
                                        </tr>
"@
                        foreach ($member in $group.Members) {
                            $htmlContent += @"
                                        <tr>
                                            <td>$($member.Name)</td>
                                            <td>$($member.objectClass)</td>
                                        </tr>
"@
                        }
                        $htmlContent += @"
                                    </table>
                                </div>
                            </td>
                        </tr>
"@
                    } elseif ($memberCount -eq 0) {
                        $htmlContent += @"
                        <tr id="members-$groupId" class="group-members-row" style="display: none;">
                            <td colspan="8">
                                <div class="nested-table-container">
                                    <em>No members in this group</em>
                                </div>
                            </td>
                        </tr>
"@
                    }
                }
                $htmlContent += "                    </table>`n                </div>`n            </div>`n        </div>`n"
            }
        }

        $htmlContent += @"
        <div class="footer">
            Generated by AD Test Environment Module | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        </div>
    </div>
</body>
</html>
"@

            # Write the HTML file
            $htmlContent | Out-File -FilePath $OutputPath -Encoding UTF8
            Write-Host "HTML report saved to: $OutputPath" -ForegroundColor Green

        } catch {
            Write-Error "Failed to generate HTML report: $($_.Exception.Message)" -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Completed HTML report generation"
    }
}
