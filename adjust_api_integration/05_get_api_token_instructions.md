# How to Get Your Adjust API Token

## Step 1: Access Adjust Dashboard

1. Log in to your Adjust dashboard at https://dash.adjust.com
2. You need Admin or Editor role to generate API tokens

## Step 2: Navigate to API Settings

1. Click on your account icon (top right corner)
2. Select "Account settings"
3. Click on "API tokens" in the left sidebar

## Step 3: Generate a New Token

1. Click "New token" or "Generate token"
2. Give it a descriptive name like "Snowflake Integration"
3. Select the appropriate permissions:
   - For Reports Service API, you need "Read" access to reporting data
4. Click "Create" or "Generate"

## Step 4: Copy and Secure the Token

1. Copy the generated token immediately (it won't be shown again)
2. Store it securely (password manager, secrets vault)

## Step 5: Update Snowflake Credentials

Run this SQL in Snowflake to store your token:

```sql
USE DATABASE WGT;
USE SCHEMA ADJUST_API;

UPDATE API_CREDENTIALS
SET CREDENTIAL_VALUE = 'YOUR_ACTUAL_TOKEN_HERE',
    UPDATED_AT = CURRENT_TIMESTAMP()
WHERE CREDENTIAL_NAME = 'ADJUST_API_TOKEN';
```

## Step 6: Get Your App Tokens

Each app in Adjust has a unique token. To find them:

1. In Adjust dashboard, go to "App settings"
2. Select your app
3. Find the "App token" (usually a 12-character alphanumeric string)

Update the app mapping table:

```sql
UPDATE WGT.ADJUST_API.APP_TOKEN_MAPPING
SET APP_TOKEN = 'your_ios_app_token_here'
WHERE APP_NAME = '1 - iOS Golf Mobile';

UPDATE WGT.ADJUST_API.APP_TOKEN_MAPPING
SET APP_TOKEN = 'your_android_app_token_here'
WHERE APP_NAME = '2 - Googleplay Golf Mobile';
```

## API Rate Limits

The Adjust Reports Service API has these limits:
- Maximum 50 simultaneous requests
- Requests that exceed timeout return 504
- Large date ranges should be split into smaller chunks

## Testing the Integration

After setting up tokens, test with:

```sql
-- Test the Snowpark function
SELECT fetch_adjust_data_snowpark(
    (SELECT CREDENTIAL_VALUE FROM WGT.ADJUST_API.API_CREDENTIALS WHERE CREDENTIAL_NAME = 'ADJUST_API_TOKEN'),
    (SELECT APP_TOKEN FROM WGT.ADJUST_API.APP_TOKEN_MAPPING WHERE APP_NAME = '1 - iOS Golf Mobile'),
    '2025-01-01',
    '2025-01-01'
);

-- If successful, run a single day load
CALL WGT.ADJUST_API.load_adjust_data_for_date(
    '2025-01-01',
    (SELECT APP_TOKEN FROM WGT.ADJUST_API.APP_TOKEN_MAPPING WHERE APP_NAME = '1 - iOS Golf Mobile'),
    '1 - iOS Golf Mobile'
);

-- Check the results
SELECT * FROM WGT.ADJUST_API.ADJ_CAMPAIGN_API LIMIT 10;
```

## Troubleshooting

**401 Unauthorized**: Token is invalid or expired. Generate a new one.

**403 Forbidden**: Token doesn't have required permissions. Check token scopes.

**429 Too Many Requests**: Rate limit exceeded. Wait and retry.

**Empty Results**: Check that:
- App token is correct
- Date range has data
- Dimensions and metrics are valid for your account
