// content.js
// This script is executed in the context of the active tab to extract chat messages.

function extractChatMessages() {
    let messages = [];

    // 1. Google Meet Chat Selectors
    // Google Meet uses div elements with 'data-message-text' or similar structures.
    // A common class for chat message content is 'oIy2qc' or 'Zmm6We', but these can change.
    const meetSelectors = [
        '.oIy2qc', // Common Google Meet message text class
        'div[data-message-text]', // Sometimes used for message wrappers
        'div[jsname="xtTewb"]' // Alternate container for messages
    ];

    meetSelectors.forEach(selector => {
        const elements = document.querySelectorAll(selector);
        elements.forEach(el => {
            if (el.innerText) {
                messages.push(el.innerText.trim());
            }
        });
    });

    // 2. Zoom Web Client Chat Selectors
    // Classes commonly found in the Zoom web client chat interface.
    const zoomSelectors = [
        '.chat-message__text-box',
        '.chat-item__chat-info-msg',
        '.chat-message__text-content',
        '.chat-message__content'
    ];

    zoomSelectors.forEach(selector => {
        const elements = document.querySelectorAll(selector);
        elements.forEach(el => {
            if (el.innerText) {
                messages.push(el.innerText.trim());
            }
        });
    });

    // 3. Generic Fallback
    // If no specific selectors match, look for elements that typically act as chat bubbles or logs.
    if (messages.length === 0) {
        // Many web apps use aria-live="polite" or role="log" for dynamic chat regions
        const liveRegions = document.querySelectorAll('[aria-live="polite"], [role="log"]');
        liveRegions.forEach(region => {
            // We push the whole text content. This might contain usernames/timestamps too.
            if (region.innerText) {
                messages.push(region.innerText.trim());
            }
        });
    }

    // Deduplicate and filter out empty strings
    const uniqueMessages = Array.from(new Set(messages)).filter(msg => msg && msg.length > 0);
    
    // Return all extracted chat messages joined by newlines
    return uniqueMessages.join('\n');
}

// In Manifest V3 with activeTab and scripting.executeScript, the result of the last executed statement
// is returned directly to the caller (popup.js).
extractChatMessages();
