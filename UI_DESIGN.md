# Page Screenshots and UI Descriptions

Since we cannot run the Flutter app in this environment, here's a detailed description of what each page looks like:

## 1. Home Page

**Layout:**
- Top: Traffic Monitor Panel (horizontal card)
  - Three columns: Upload (blue) | Download (green) | Total (orange)
  - Each shows icon, label, and formatted traffic size
  
**Cards below:**
1. Current Profile Card
   - Icon: Article icon
   - Shows profile name or "No active profile"
   
2. Selected Node Card
   - Icon: Router icon
   - Shows selected proxy node name (default: "DIRECT")
   
3. Proxy Mode Card
   - Icon: Security icon
   - Shows current mode (Rule/Global/Direct)
   
4. Network Settings Card
   - Icon: Settings ethernet icon
   - Shows "Mixed Port: 7890" and "Allow LAN: No"
   
5. IP Information Card
   - Icon: Public/globe icon
   - Shows IP address and country
   
6. System Info Card
   - Icon: Computer icon
   - Shows system proxy status and connection count

## 2. Proxies Page

**Top Section:**
- Left: "Proxy Mode: Rule" text
- Right: Segmented button with 3 options (Rule/Global/Direct)

**List Section:**
- Cards for each proxy node:
  - Left: Circle icon (green checkmark if active, grey circle if not)
  - Center: Node name (bold if active) + "Type: [type]"
  - Right: Colored chip showing latency (e.g., "123ms")
    - Green background: < 100ms
    - Orange background: 100-200ms
    - Red background: > 200ms

**Example proxies:**
- DIRECT (active)
- HK-01 (Shadowsocks, 123ms)
- US-02 (VMess, 256ms)
- JP-03 (Trojan, 89ms)

## 3. Profiles Page

**Top Section:**
- Left: "Profiles" title
- Right: "+ Add Profile" button

**List Section:**
- If empty: Center text "No profiles yet. Click + to add one."
- If has profiles: Cards with:
  - Left: Article icon (green if active, grey if not)
  - Center: Profile name, update time, URL
  - Right: Delete (trash) icon

**Add Profile Dialog:**
- Title: "Add Profile"
- Two text fields:
  - Profile Name
  - Subscription URL
- Cancel and Add buttons

## 4. Connections Page

**Top Section:**
- Left: "Active Connections: [count]"
- Right: "Clear" button

**List Section:**
- If empty: Center text "No active connections"
- If has connections: Expandable cards with:
  - Collapsed: Icon + Host + Type/Network
  - Expanded: Details table
    - Source: IP:Port
    - Destination: IP:Port
    - Upload: Formatted bytes
    - Download: Formatted bytes
    - Start Time: HH:MM:SS

## 5. Rules Page

**Top Section:**
- "Rules (4)" title

**List Section:**
- Cards for each rule:
  - Left: Colored circle with icon
    - Blue: DOMAIN-SUFFIX
    - Green: DOMAIN-KEYWORD
    - Orange: IP-CIDR
    - Purple: GEOIP
  - Center: Rule type and payload
  - Right: Chip with proxy name

**Example rules:**
- DOMAIN-SUFFIX: google.com → DIRECT
- DOMAIN-KEYWORD: github → Proxy
- IP-CIDR: 192.168.0.0/16 → DIRECT
- GEOIP: CN → DIRECT

## 6. Logs Page

**Top Section:**
- Left: "Logs ([count])"
- Right: "Clear" button

**List Section:**
- If empty: Center text "No logs yet"
- If has logs: Cards with:
  - Left: Colored icon based on level
    - Red error icon: ERROR
    - Orange warning icon: WARNING
    - Blue info icon: INFO
    - Grey bug icon: DEBUG
  - Center: Log message
  - Bottom: "LEVEL • HH:MM:SS" in matching color

## 7. Test Page

**Top Section:**
- Title: "Proxy Speed Test"
- Button: "Start Test" (or "Testing..." with spinner when running)

**List Section:**
- If no results: Center text "Click 'Start Test' to begin testing proxies"
- If has results: Cards with:
  - Left: Green checkmark (success) or red error icon (failure)
  - Center: Proxy name and message
  - Right: Colored chip with latency (if successful)

**Testing Process:**
- Tests each proxy sequentially with 500ms delay
- Shows real-time results as testing progresses
- Simulates realistic delays and success/failure

## 8. Settings Page

**General Settings Section:**

1. System Proxy Card
   - Switch: Enable/disable system proxy
   - Description: "Use system proxy settings"

2. Allow LAN Card
   - Switch: Enable/disable LAN connections
   - Description: "Allow connections from LAN"

3. Mixed Port Card
   - Shows current port number
   - Tap to open edit dialog
   - Dialog has number input field

**About Section:**

1. Version Card
   - Icon: Info icon
   - Shows "1.0.0"

2. Framework Card
   - Icon: Code icon
   - Shows "Flutter 3.35.4 (Dart 3.9.2)"

3. License Card
   - Icon: Description icon
   - Shows "MIT License"
   - Tappable to view full license page

## Bottom Navigation Bar

8 tabs with icons and labels:
1. Home (house icon)
2. Proxies (router icon)
3. Profiles (article icon)
4. Connections (swap arrows icon)
5. Rules (rule icon)
6. Logs (description icon)
7. Test (speedometer icon)
8. Settings (settings icon)

**Behavior:**
- Active tab highlighted in primary color
- Inactive tabs in grey
- Smooth transition when switching tabs
- Material 3 design with animated selection indicator

## Theme Support

**Light Theme:**
- White/light grey backgrounds
- Dark text
- Blue primary color
- High contrast for readability

**Dark Theme:**
- Dark grey/black backgrounds
- Light text
- Blue primary color (adjusted for dark mode)
- Comfortable for night viewing

**Automatic:**
- Follows system theme preference
- Seamless switching
- All colors optimized for both themes

## Visual Design Patterns

**Cards:**
- Rounded corners (8px radius)
- Subtle elevation/shadow
- 16px horizontal padding
- 4px vertical margin between cards

**Icons:**
- Material Design icons
- 24px size for list items
- 20px size for chips
- Semantic colors (green=success, red=error, etc.)

**Typography:**
- Title Large: Page headers
- Title Medium: Section headers
- Body Medium: Regular text
- Body Small: Descriptions
- All text scales with system font size

**Colors:**
- Primary: Blue (#0175C2)
- Success: Green
- Warning: Orange
- Error: Red
- Info: Blue
- Neutral: Grey shades

**Spacing:**
- Standard padding: 16px
- Card margins: 4-12px
- Section spacing: 20-24px
- Consistent throughout app

## Accessibility

- High contrast text
- Minimum touch target size: 48x48px
- Screen reader support (through Flutter)
- Keyboard navigation support
- Semantic labels on all interactive elements

## Responsive Design

- Adapts to different screen sizes
- Scrollable content areas
- Bottom navigation for easy thumb reach
- Cards stack vertically on all screen sizes
- Horizontal layout for traffic monitor on wide screens

This comprehensive UI design ensures a modern, clean, and user-friendly experience similar to clash-verge-rev but with Flutter's cross-platform advantages.
