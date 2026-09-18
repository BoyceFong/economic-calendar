() => {
    const rows = [];
    const tables = document.querySelectorAll('table');
    if (!tables.length) return rows;

    // Find the calendar table
    let bestTable = null;
    let bestCount = 0;
    tables.forEach(t => {
        const c = t.querySelectorAll('tr').length;
        const isDataTable = t.className.includes('datatable-v2');
        if (isDataTable && c > bestCount) {
            bestCount = c;
            bestTable = t;
        }
    });
    if (!bestTable) {
        tables.forEach(t => {
            const c = t.querySelectorAll('tr').length;
            if (c > bestCount) {
                bestCount = c;
                bestTable = t;
            }
        });
    }
    if (!bestTable) return rows;

    let currentDate = '';
    const allRows = bestTable.querySelectorAll('tr');

    for (let ri = 0; ri < allRows.length; ri++) {
        const tr = allRows[ri];
        const tds = tr.querySelectorAll('td');

        // Date separator: single td with colspan
        if (tds.length === 1 && tds[0].getAttribute('colspan')) {
            const dateText = (tds[0].textContent || '').trim();
            if (dateText && /[A-Z][a-z]+,\s+[A-Z][a-z]+\s+\d{1,2},?\s+\d{4}/.test(dateText)) {
                currentDate = dateText;
            }
            continue;
        }

        if (tds.length < 8) continue;

        // Time: cell[1] (desktop) or cell[0] (mobile)
        let timeText = (tds[1]?.textContent || '').trim();
        if (!timeText || timeText.length < 4) {
            const mobileText = (tds[0]?.textContent || '').trim();
            const m = mobileText.match(/(\d{1,2}:\d{2})/);
            if (m) timeText = m[1];
        }
        if (timeText) {
            const tm = timeText.match(/(\d{1,2}:\d{2})/);
            if (tm) timeText = tm[1];
        }

        // Country code: cell[2] (desktop) - check img alt/text
        let countryCode = '';
        const ccCell = tds[2];
        if (ccCell) {
            // Check for img with alt/title
            const flagImg = ccCell.querySelector('img');
            if (flagImg) {
                countryCode = (flagImg.getAttribute('alt') || flagImg.getAttribute('title') || '').trim();
            }
            // Check text content
            if (!countryCode || countryCode.length !== 2) {
                const txt = (ccCell.textContent || '').trim();
                const mm = txt.match(/([A-Z]{2,3})/);
                if (mm) countryCode = mm[1];
            }
        }
        // Fallback to mobile cell
        if (!countryCode || countryCode.length < 2) {
            const mobileText = (tds[0]?.textContent || '').trim();
            const m = mobileText.match(/\d{1,2}:\d{2}\s*([A-Z]{2,3})/);
            if (m) countryCode = m[1];
        }
        if (countryCode === 'EUR') countryCode = 'EU';

        // Event name and URL from <a> in cell[3]
        const evCell = tds[3];
        let eventName = '';
        let eventUrl = '';
        const eventLink = evCell ? evCell.querySelector('a') : null;
        if (eventLink) {
            eventName = (eventLink.textContent || '').trim();
            eventUrl = eventLink.getAttribute('href') || '';
        }
        if (!eventName && evCell) {
            const fullText = (evCell.textContent || '').trim();
            const actIdx = fullText.search(/Act:|Forecast:|Previous:|Actual:/i);
            eventName = actIdx > 0 ? fullText.substring(0, actIdx).trim() : fullText;
        }
        eventName = eventName.replace(/\s+/g, ' ').trim();
        // Make URL absolute if relative
        if (eventUrl && !eventUrl.startsWith('http')) {
            eventUrl = 'https://www.investing.com' + (eventUrl.startsWith('/') ? '' : '/') + eventUrl;
        }

        // Importance: count filled (opacity-60) stars in cell[4]
        const impCell = tds[4];
        let bullCount = 0;
        if (impCell) {
            const svgs = impCell.querySelectorAll('svg');
            svgs.forEach(svg => {
                const cls = svg.getAttribute('class') || '';
                const parentCls = svg.parentElement ? (svg.parentElement.getAttribute('class') || '') : '';
                if (cls.includes('opacity-60') || parentCls.includes('opacity-60') ||
                    cls.includes('filled') || cls.includes('full')) {
                    bullCount++;
                }
            });
            // Fallback: check fill color
            if (bullCount === 0) {
                svgs.forEach(svg => {
                    const fill = svg.getAttribute('fill') || '';
                    if (fill && fill !== 'none' && fill !== 'transparent' && fill !== '#86868b' && fill !== 'gray') {
                        bullCount++;
                    }
                });
            }
        }
        // Mobile fallback
        if (bullCount === 0) {
            const mobileSvgs = tds[0].querySelectorAll('svg');
            mobileSvgs.forEach(svg => {
                const cls = svg.getAttribute('class') || '';
                if (cls.includes('opacity-60')) bullCount++;
            });
        }
        if (bullCount === 0) bullCount = 1;
        if (bullCount > 3) bullCount = 3;

        // Values
        const actual = (tds[5]?.textContent || '').trim() || null;
        const forecast = (tds[6]?.textContent || '').trim() || null;
        const previous = (tds[7]?.textContent || '').trim() || null;

        if (eventName && timeText && countryCode) {
            rows.push({
                date: currentDate,
                time: timeText,
                countryCode: countryCode,
                bull: bullCount,
                name: eventName,
                url: eventUrl,
                actual: actual,
                forecast: forecast,
                previous: previous,
            });
        }
    }
    return rows;
}
