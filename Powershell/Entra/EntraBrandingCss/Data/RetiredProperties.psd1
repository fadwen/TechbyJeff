@{
    <#
        The CSS properties Microsoft Entra ID is retiring from company branding custom CSS, and
        a short list of near misses worth a human look.

        This is the only file to edit when Microsoft changes the list. Nothing else in the
        module names a property.

        Source of the Retired list, under "Deprecated properties":
            https://learn.microsoft.com/entra/fundamentals/reference-company-branding-css-template
        Raw Markdown, which is what the list below was diffed against, in MicrosoftDocs/entra-docs:
            docs/fundamentals/reference-company-branding-css-template.md

        How the count works. The Learn page shows 49 bullets. Two of them carry included
        longhands in parentheses: "position (including top, right, bottom, left, and z-index)"
        and "margin (including margin-top, margin-bottom, margin-left, and margin-right)".
        Counting every name a declaration can actually use gives 49 + 5 + 4 = 58 entries, and
        58 is what this file holds. Bullet records which Learn bullet each name came from.

        FirstListedIn records where each name was first announced, as far as could be found:
            MC1435782   Message Center, published 2026-07-21. 10 bullets, 19 names.
            MC1458474   Message Center, published 2026-08-21. 28 further names.
            Learn       On the Learn page as of ms.date 2026-08-18 and in neither Message
                        Center post. 11 names, including display and visibility.
        A tenant checked only against the first post can be missing 39 names.
    #>

    SourceUrl   = 'https://learn.microsoft.com/entra/fundamentals/reference-company-branding-css-template'
    SourceDate  = '2026-08-18'
    VerifiedOn  = '2026-10-19'

    Retired = @(
        # MC1435782, 2026-07-21: the original ten bullets
        @{ Property = 'position';       Bullet = 'position'; FirstListedIn = 'MC1435782' }
        @{ Property = 'top';            Bullet = 'position'; FirstListedIn = 'MC1435782' }
        @{ Property = 'right';          Bullet = 'position'; FirstListedIn = 'MC1435782' }
        @{ Property = 'bottom';         Bullet = 'position'; FirstListedIn = 'MC1435782' }
        @{ Property = 'left';           Bullet = 'position'; FirstListedIn = 'MC1435782' }
        @{ Property = 'z-index';        Bullet = 'position'; FirstListedIn = 'MC1435782' }
        @{ Property = 'margin';         Bullet = 'margin';   FirstListedIn = 'MC1435782' }
        @{ Property = 'margin-top';     Bullet = 'margin';   FirstListedIn = 'MC1435782' }
        @{ Property = 'margin-bottom';  Bullet = 'margin';   FirstListedIn = 'MC1435782' }
        @{ Property = 'margin-left';    Bullet = 'margin';   FirstListedIn = 'MC1435782' }
        @{ Property = 'margin-right';   Bullet = 'margin';   FirstListedIn = 'MC1435782' }
        @{ Property = 'transform';      Bullet = 'transform';      FirstListedIn = 'MC1435782' }
        @{ Property = 'opacity';        Bullet = 'opacity';        FirstListedIn = 'MC1435782' }
        @{ Property = 'overflow';       Bullet = 'overflow';       FirstListedIn = 'MC1435782' }
        @{ Property = 'filter';         Bullet = 'filter';         FirstListedIn = 'MC1435782' }
        @{ Property = 'pointer-events'; Bullet = 'pointer-events'; FirstListedIn = 'MC1435782' }
        @{ Property = 'clip-path';      Bullet = 'clip-path';      FirstListedIn = 'MC1435782' }
        @{ Property = 'mix-blend-mode'; Bullet = 'mix-blend-mode'; FirstListedIn = 'MC1435782' }
        @{ Property = 'translate';      Bullet = 'translate';      FirstListedIn = 'MC1435782' }

        # On the Learn page, in neither Message Center post
        @{ Property = '-webkit-transform'; Bullet = '-webkit-transform'; FirstListedIn = 'Learn' }
        @{ Property = '-moz-transform';    Bullet = '-moz-transform';    FirstListedIn = 'Learn' }
        @{ Property = '-ms-transform';     Bullet = '-ms-transform';     FirstListedIn = 'Learn' }
        @{ Property = '-o-transform';      Bullet = '-o-transform';      FirstListedIn = 'Learn' }
        @{ Property = 'scale';             Bullet = 'scale';             FirstListedIn = 'Learn' }
        @{ Property = 'rotate';            Bullet = 'rotate';            FirstListedIn = 'Learn' }
        @{ Property = 'perspective';       Bullet = 'perspective';       FirstListedIn = 'Learn' }
        @{ Property = 'display';           Bullet = 'display';           FirstListedIn = 'Learn' }
        @{ Property = 'visibility';        Bullet = 'visibility';        FirstListedIn = 'Learn' }
        @{ Property = 'inset';             Bullet = 'inset';             FirstListedIn = 'Learn' }
        @{ Property = 'zoom';              Bullet = 'zoom';              FirstListedIn = 'Learn' }

        # MC1458474, 2026-08-21: the second batch
        @{ Property = 'offset';              Bullet = 'offset';              FirstListedIn = 'MC1458474' }
        @{ Property = 'offset-path';         Bullet = 'offset-path';         FirstListedIn = 'MC1458474' }
        @{ Property = 'offset-distance';     Bullet = 'offset-distance';     FirstListedIn = 'MC1458474' }
        @{ Property = 'margin-block';        Bullet = 'margin-block';        FirstListedIn = 'MC1458474' }
        @{ Property = 'margin-block-start';  Bullet = 'margin-block-start';  FirstListedIn = 'MC1458474' }
        @{ Property = 'margin-block-end';    Bullet = 'margin-block-end';    FirstListedIn = 'MC1458474' }
        @{ Property = 'margin-inline';       Bullet = 'margin-inline';       FirstListedIn = 'MC1458474' }
        @{ Property = 'margin-inline-start'; Bullet = 'margin-inline-start'; FirstListedIn = 'MC1458474' }
        @{ Property = 'margin-inline-end';   Bullet = 'margin-inline-end';   FirstListedIn = 'MC1458474' }
        @{ Property = 'order';               Bullet = 'order';               FirstListedIn = 'MC1458474' }
        @{ Property = 'grid-area';           Bullet = 'grid-area';           FirstListedIn = 'MC1458474' }
        @{ Property = 'grid-column';         Bullet = 'grid-column';         FirstListedIn = 'MC1458474' }
        @{ Property = 'grid-column-start';   Bullet = 'grid-column-start';   FirstListedIn = 'MC1458474' }
        @{ Property = 'grid-column-end';     Bullet = 'grid-column-end';     FirstListedIn = 'MC1458474' }
        @{ Property = 'grid-row';            Bullet = 'grid-row';            FirstListedIn = 'MC1458474' }
        @{ Property = 'grid-row-start';      Bullet = 'grid-row-start';      FirstListedIn = 'MC1458474' }
        @{ Property = 'grid-row-end';        Bullet = 'grid-row-end';        FirstListedIn = 'MC1458474' }
        @{ Property = 'isolation';           Bullet = 'isolation';           FirstListedIn = 'MC1458474' }
        @{ Property = 'overflow-x';          Bullet = 'overflow-x';          FirstListedIn = 'MC1458474' }
        @{ Property = 'overflow-y';          Bullet = 'overflow-y';          FirstListedIn = 'MC1458474' }
        @{ Property = 'overflow-block';      Bullet = 'overflow-block';      FirstListedIn = 'MC1458474' }
        @{ Property = 'overflow-inline';     Bullet = 'overflow-inline';     FirstListedIn = 'MC1458474' }
        @{ Property = 'content-visibility';  Bullet = 'content-visibility';  FirstListedIn = 'MC1458474' }
        @{ Property = 'clip';                Bullet = 'clip';                FirstListedIn = 'MC1458474' }
        @{ Property = 'mask';                Bullet = 'mask';                FirstListedIn = 'MC1458474' }
        @{ Property = 'mask-image';          Bullet = 'mask-image';          FirstListedIn = 'MC1458474' }
        @{ Property = '-webkit-mask';        Bullet = '-webkit-mask';        FirstListedIn = 'MC1458474' }
        @{ Property = '-webkit-mask-image';  Bullet = '-webkit-mask-image';  FirstListedIn = 'MC1458474' }
    )

    <#
        Review entries are not on Microsoft's list and are never reported as Retired. They are
        the near misses an admin should read with their own eyes, because each one can do the
        same job as a retired property. Keep this list short, and do not promote anything from
        here to Retired without Microsoft listing it.
    #>
    Review = @(
        @{
            Property = '-webkit-filter'
            Reason   = 'Vendor form of filter, which is retired. Microsoft lists only the unprefixed name.'
        }
        @{
            Property = '-webkit-clip-path'
            Reason   = 'Vendor form of clip-path, which is retired. Microsoft lists only the unprefixed name.'
        }
        @{
            Property = 'all'
            Reason   = 'Shorthand that resets every property, including display and visibility, which are retired.'
        }
        @{
            Property = 'inset-block'
            Reason   = 'Logical form of top and bottom. inset is retired; its logical longhands are not listed.'
        }
        @{
            Property = 'inset-block-start'
            Reason   = 'Logical form of top. inset is retired; its logical longhands are not listed.'
        }
        @{
            Property = 'inset-block-end'
            Reason   = 'Logical form of bottom. inset is retired; its logical longhands are not listed.'
        }
        @{
            Property = 'inset-inline'
            Reason   = 'Logical form of left and right. inset is retired; its logical longhands are not listed.'
        }
        @{
            Property = 'inset-inline-start'
            Reason   = 'Logical form of left. inset is retired; its logical longhands are not listed.'
        }
        @{
            Property = 'inset-inline-end'
            Reason   = 'Logical form of right. inset is retired; its logical longhands are not listed.'
        }
    )
}
