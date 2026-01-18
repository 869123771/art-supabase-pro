# Art Design Pro (Supabase Pro)

Art Design Pro is a modern backend management system template built with **Vue 3**, **TypeScript**, **Element Plus**, and **Supabase**. It provides rich functional components, comprehensive permission control, and ready-to-use system management modules, designed to help developers rapidly build high-performance enterprise applications.

## ✨ Features

- **Modern Tech Stack**: Built on Vue 3 + Vite + TypeScript + Pinia.
- **Backend-as-a-Service Integration**: Deeply integrated with Supabase for authentication, database, and real-time subscription support.
- **Enhanced User Experience**:
  - 🌗 Supports light/dark mode switching.
  - 🔒 Supports screen locking, multi-level permission control (RBAC), and JWT authentication.
  - 🔍 Global search and WorkTab navigation.
  - 📱 Responsive layout compatible with both mobile and desktop devices.
- **Rich Component Library**:
  - 📊 Integrated with ECharts, supporting multiple chart types (line, bar, candlestick, radar, etc.).
  - 📋 Intelligent table component with column configuration, fixed headers, and virtual scrolling.
  - 📝 Dynamic form component with Excel import/export support.
  - 🖼️ Image and video processing components.
- **i18n Internationalization**: Built-in Chinese and English language packs.
- **Development Assistance**:
  - 🧹 Automated cleanup script (clean-dev.ts).
  - 📝 Upgrade log management.
  - 🔧 Powerful settings panel to dynamically adjust layout, colors, navigation, and more.

## 🛠️ Tech Stack

- **Build Tool**: Vite  
- **Framework**: Vue 3 (Composition API)  
- **Language**: TypeScript  
- **UI Component Library**: Element Plus  
- **State Management**: Pinia  
- **Routing**: Vue Router  
- **Charts**: Apache ECharts  
- **Backend Service**: Supabase  
- **Styling**: SCSS + Tailwind CSS  
- **HTTP Client**: Axios  
- **Internationalization**: Vue I18n  

## 📂 Project Structure

```
art-supbase-pro/
├── public/                 # Static assets
├── src/
│   ├── api/                # API definitions (connected to Supabase)
│   ├── assets/             # Static resources (images, fonts, etc.)
│   ├── components/         # Business components
│   │   └── core/           # Core business components (Charts, Forms, Layouts, Tables)
│   ├── config/             # App configuration (routes, shortcuts, theme, etc.)
│   ├── directives/         # Custom directives (Auth, Roles, Highlight)
│   ├── hooks/              # Composition functions (useTable, useAuth, useTheme)
│   ├── locales/            # Internationalization language packs
│   ├── router/             # Route configuration and guards
│   ├── store/              # Pinia state management
│   ├── types/              # TypeScript type definitions
│   ├── utils/              # Utility functions (Http, Tree, Format, Storage)
│   ├── views/              # Page views
│   │   ├── auth/           # Login, registration, password recovery
│   │   ├── dashboard/      # Dashboard homepage
│   │   ├── system/         # System management (users, roles, menus)
│   │   └── data-center/    # Data center (dictionaries, attachments)
│   ├── App.vue             # Root component
│   └── main.ts             # Entry file
├── .env                    # Environment variables
├── vite.config.ts          # Vite configuration
└── package.json
```

## 🚀 Quick Start

### Prerequisites

Ensure you have [Node.js](https://nodejs.org/) (v16+) and [pnpm](https://pnpm.io/) installed in your environment.

### Install Dependencies

```bash
# Install dependencies using pnpm
pnpm install
```

### Configure Environment Variables

Create or modify the `.env` file in the project root directory and configure your Supabase connection details:

```env
VITE_SUPABASE_URL=your_supabase_project_url
VITE_SUPABASE_KEY=your_supabase_anon_key
VITE_API_URL=your_api_server_url
```

### Start Development Server

```bash
pnpm dev
```

After the server starts, open your browser and navigate to `http://localhost:3000` (default port).

### Build for Production

```bash
pnpm build
```

### Clean Development Environment (Optional)

This project includes a development helper script to clean route caches and leftover changelog files:

```bash
pnpm clean
```

## 📝 Main Modules Overview

1. **System Management**: Includes user management, role management, and menu management. Permissions are granular down to the button level.
2. **Data Center**: Provides dictionary data maintenance and attachment management.
3. **Dashboard**: Displays key system metrics with cards for sales overview, user statistics, to-do items, and more.
4. **Authentication (Auth)**: Supports username/password login, registration, third-party integration (requires Supabase Auth configuration), and password recovery.

## 📄 License

This project is open-sourced under the [MIT](LICENSE) license.

## 🤝 Contributing

Feel free to submit Issues or Pull Requests to help improve the project.