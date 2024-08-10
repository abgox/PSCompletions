#
# Module manifest for module 'PSCompletions'
#
# Generated by: abgox
#
# Generated on: 2023/8/15
#

@{

    RootModule        = 'PSCompletions.psm1'

    ModuleVersion     = '4.2.4'

    GUID              = '00929632-527d-4dab-a5b3-21197faccd05'

    Author            = 'abgox'

    Copyright         = '(c) abgox. All rights reserved.'

    Description       = 'A completion manager for better and simpler use powershell completions. For more information, please visit the project: https://github.com/abgox/PSCompletions | https://gitee.com/abgox/PSCompletions'
    ScriptsToProcess  = 'core\init.ps1'

    FunctionsToExport = 'PSCompletions'

    PrivateData       = @{

        PSData = @{

            Tags       = @('PowerShell', 'pwsh', 'Tab', 'PS-Completions', 'Dynamic', 'Multi-language', 'base-in-json' , 'Completion-Manager')

            LicenseUri = 'https://github.com/abgox/PSCompletions/blob/main/LICENSE'

            ProjectUri = 'https://github.com/abgox/PSCompletions'

        }

    }
}

