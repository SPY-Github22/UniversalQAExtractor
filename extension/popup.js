// popup.js
// Handles the logic for the extension popup UI.

document.addEventListener('DOMContentLoaded', () => {
    const extractBtn = document.getElementById('extract-btn');
    const resultsDiv = document.getElementById('results');

    // Add click event listener to the main button
    extractBtn.addEventListener('click', async () => {
        // 1. Update UI to indicate loading state
        extractBtn.disabled = true;
        resultsDiv.textContent = 'Scraping chat from the page...';
        resultsDiv.className = 'loading';

        try {
            // 2. Get the current active tab where the user invoked the extension
            const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });

            if (!tab) {
                throw new Error("No active tab found.");
            }

            // 3. Inject and execute the content script (content.js) into the active tab
            // The scripting permission allows us to execute files directly.
            const injectionResults = await chrome.scripting.executeScript({
                target: { tabId: tab.id },
                files: ['content.js']
            });

            // The result of the content script is captured here
            const chatText = injectionResults[0]?.result;

            if (!chatText || chatText.trim() === '') {
                resultsDiv.textContent = 'No chat messages found. Please ensure the meeting chat panel is open and contains text.';
                resultsDiv.className = '';
                extractBtn.disabled = false;
                return;
            }

            // 4. Update UI to show that API request is in progress
            resultsDiv.textContent = `Found ${chatText.split('\n').length} chat messages. Analyzing to extract top questions...\n(This may take a few moments)`;

            // 5. Send the extracted text to the local backend API
            const response = await fetch('http://localhost:5000/extract', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                // Send the chat data as JSON
                body: JSON.stringify({ chat: chatText })
            });

            // Check if the network request was successful
            if (!response.ok) {
                throw new Error(`Server responded with status: ${response.status}`);
            }

            // 6. Parse the JSON response from the server
            const data = await response.json();

            // Support a few common response structures (adjust as needed based on backend implementation)
            const questions = data.questions || data.top_questions || data.result;

            if (questions) {
                // Display the successfully extracted questions
                // If it's an array/object, pretty-print it. If it's a string, show it directly.
                resultsDiv.textContent = typeof questions === 'string' ? questions : JSON.stringify(questions, null, 2);
                resultsDiv.className = '';
            } else {
                // If the response structure wasn't what we expected
                resultsDiv.textContent = 'Received successful response from server, but could not find the questions payload.\n\nRaw Response: ' + JSON.stringify(data);
                resultsDiv.className = '';
            }

        } catch (error) {
            // 7. Handle any errors during scraping or API fetching
            console.error('QA Extraction Error:', error);
            
            if (error.message.includes('Failed to fetch') || error.message.includes('NetworkError')) {
                resultsDiv.textContent = `Connection Error: Could not connect to the local server.\n\nPlease make sure your backend is running at http://localhost:5000`;
            } else {
                resultsDiv.textContent = `Error: ${error.message}`;
            }
            resultsDiv.className = 'error';
        } finally {
            // 8. Re-enable the button regardless of success or failure
            extractBtn.disabled = false;
        }
    });
});
