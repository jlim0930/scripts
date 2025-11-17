#!/usr/bin/env bash

# This script will  answer quick questions about shell commmands and elasticsearch related topics
# using the Gemini API from Google Cloud's Generative AI models.
# you will need to create ~/.env file with GEMINI_API_KEY variable set.

# Stop the script if any command fails
set -e

# Check for Dependencies
if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' is not installed." >&2
    echo "Please install it to parse the API response (e.g., 'brew install jq' or 'apt install jq')." >&2
    exit 1
fi

if ! command -v curl &> /dev/null; then
    echo "Error: 'curl' is not installed." >&2
    echo "Please install it to make the API call (e.g., 'apt install curl')." >&2
    exit 1
fi

# Load API Key
ENV_FILE="$HOME/.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "Error: API key file not found at $ENV_FILE" >&2
    exit 1
fi

# Load the .env file
export $(grep -v '^#' "$ENV_FILE" | xargs)

if [ -z "$GEMINI_API_KEY" ]; then
    echo "Error: GEMINI_API_KEY is not set in $ENV_FILE" >&2
    exit 1
fi

# Find Latest "Pro" Model
LIST_MODELS_URL="https://generativelanguage.googleapis.com/v1beta/models?key=${GEMINI_API_KEY}"

# Make the API call to list models
MODEL_RESPONSE=$(curl -s -X GET "$LIST_MODELS_URL")

# Parse the response to find the latest "pro" model that supports generateContent
MODEL_NAME=$(echo "$MODEL_RESPONSE" | jq -r '
    .models |
    map(
        select(
            (.name | (contains("pro") and (contains("flash") | not))) and
            (.supportedGenerationMethods | index("generateContent"))
        )
    ) |
    map(.name) |
    sort |
    reverse |
    .[0]
')

# Check if we successfully found a model
if [ -z "$MODEL_NAME" ] || [ "$MODEL_NAME" == "null" ]; then
    echo "Error: Could not find a suitable 'pro' model." >&2
    echo "API Response: $MODEL_RESPONSE" >&2
    exit 1
fi

# Check if a question was provided
if [ -z "$*" ]; then
    echo "Usage: ask \"Your question here\""
    echo "Example: ask \"how to find files modified in the last 2 days\""
    exit 1
fi

USER_QUESTION="$*"
echo "Asking Gemini..."

# This prompt is tuned for terminal-friendly, concise answers.
PROMPT_TEXT="You are an expert-level CLI and API assistant. Provide a brief, concise answer to the user's question.
Format the response for a terminal window. Use Markdown code fences (\`\`\`) for any shell commands, code, or API examples.
Be direct and to the point, but ensure the answer is correct and complete."

# Use jq --arg to safely pass the variables
JSON_PAYLOAD=$(jq -n \
                  --arg prompt "$PROMPT_TEXT" \
                  --arg question "$USER_QUESTION" \
                  '{
                    "contents": [
                      {
                        "parts": [
                          {"text": $prompt},
                          {"text": $question}
                        ]
                      }
                    ],
                    "generationConfig": {
                      "temperature": 0.2,
                      "maxOutputTokens": 2048
                    }
                  }')

API_URL="https://generativelanguage.googleapis.com/v1beta/${MODEL_NAME}:generateContent?key=${GEMINI_API_KEY}"

API_RESPONSE=$(curl -s -X POST \
     -H "Content-Type: application/json" \
     -d "$JSON_PAYLOAD" \
     "$API_URL")

# Parse the raw text
ANSWER=$(echo "$API_RESPONSE" | jq -r '.candidates[0].content.parts[0].text')

# Handle API errors
if [ -z "$ANSWER" ] || [ "$ANSWER" == "null" ]; then
    echo "Error: Failed to get an answer from Gemini." >&2
    echo "API Response: $API_RESPONSE" >&2
    exit 1
fi

# Strip markdown for cleaner terminal output
CLEAN_ANSWER=$(echo "$ANSWER" | sed \
    -e '/^```/d' \
    -e 's/^\* \s*//'
)

# Print the cleaned answer.
printf "\n%s\n" "$CLEAN_ANSWER"
