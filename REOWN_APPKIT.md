# Reown AppKit Integration Guide

## 🚀 Overview

MegaETH Launch Kit Pro is now integrated with **Reown AppKit** (formerly WalletConnect) for seamless wallet connectivity and multi-chain support.

## 📦 Installation

### Prerequisites

- Node.js 16+ 
- npm or yarn
- Next.js 14+

### Setup Steps

1. **Install Dependencies**

```bash
npm install @reown/appkit @reown/appkit-adapter-wagmi @reown/appkit-react wagmi viem @tanstack/react-query
```

2. **Get Your Project ID**

- Visit [Reown Cloud](https://cloud.reown.com)
- Create a new project
- Copy your Project ID

3. **Configure Environment Variables**

Create a `.env.local` file:

```env
NEXT_PUBLIC_REOWN_PROJECT_ID=your_project_id_here
NEXT_PUBLIC_MEGA_PAY_PRO_ADDRESS=0x...
NEXT_PUBLIC_MEGA_COMMERCE_ADDRESS=0x...
NEXT_PUBLIC_MEGA_PAYMENTS_ADDRESS=0x...
```

4. **Configure AppKit**

The AppKit is configured in `app/appkit-config.ts`. Update the chains and metadata as needed:

```typescript
import { createAppKit } from '@reown/appkit/react'
import { WagmiAdapter } from '@reown/appkit-adapter-wagmi'
import { mainnet, arbitrum, polygon, optimism, base } from 'wagmi/chains'

export const projectId = process.env.NEXT_PUBLIC_REOWN_PROJECT_ID

const wagmiAdapter = new WagmiAdapter({
  chains: [mainnet, arbitrum, polygon, optimism, base],
  projectId
})

export const appKit = createAppKit({
  adapters: [wagmiAdapter],
  projectId,
  metadata: {
    name: 'MegaETH Launch Kit Pro',
    description: 'Professional enterprise-grade toolkit',
    url: 'https://megaeth.org',
    icons: ['https://megaeth.org/logo.png']
  }
})
```

## 🎯 Usage

### Basic Wallet Connection

```tsx
'use client'

import { useAccount } from 'wagmi'
import { appKit } from './appkit-config'

export function WalletButton() {
  const { address, isConnected } = useAccount()

  return (
    <button onClick={() => appKit.open()}>
      {isConnected ? address : 'Connect Wallet'}
    </button>
  )
}
```

### Interacting with MegaETH Contracts

```tsx
'use client'

import { useWriteContract } from 'wagmi'
import { parseEther } from 'viem'

export function MegaPayProComponent() {
  const { writeContract, isPending } = useWriteContract()

  const handlePayFees = () => {
    writeContract({
      address: '0x...', // Your contract address
      abi: MEGA_PAY_PRO_ABI,
      functionName: 'payFeesWithSignature',
      args: [tokenAddress, gasUsed, nonce, signature]
    })
  }

  return (
    <button onClick={handlePayFees} disabled={isPending}>
      Pay Fees
    </button>
  )
}
```

## 🔧 Features

### Supported Wallets

Reown AppKit supports 300+ wallets including:
- MetaMask
- WalletConnect
- Coinbase Wallet
- Rainbow Wallet
- Trust Wallet
- And many more...

### Supported Chains

- Ethereum Mainnet
- Polygon
- Arbitrum
- Optimism
- Base
- MegaETH (when available)

### Social Login

Reown AppKit supports social login options:
- Google
- X (Twitter)
- GitHub
- Discord
- Apple
- Facebook

## 📚 Documentation

- [Reown AppKit Docs](https://docs.reown.com/appkit)
- [Wagmi Documentation](https://wagmi.sh)
- [Viem Documentation](https://viem.sh)

## 🛠 Cursor IDE Support

If you're using Cursor IDE, the `.cursor/reown-appkit.mdc` file provides:
- Type hints for Reown AppKit
- Cursor-specific rules
- Enhanced autocomplete
- Better development experience

## 🚀 Deployment

### Vercel

```bash
vercel deploy
```

### Other Platforms

Make sure to set environment variables:
- `NEXT_PUBLIC_REOWN_PROJECT_ID`
- Contract addresses

## 🔒 Security Best Practices

1. **Never expose private keys** in client-side code
2. **Validate all user inputs** before sending transactions
3. **Use environment variables** for sensitive data
4. **Implement proper error handling** for failed transactions
5. **Test thoroughly** on testnets before mainnet deployment

## 📞 Support

- [Reown Documentation](https://docs.reown.com)
- [MegaETH Documentation](./DOCUMENTATION.md)
- [GitHub Issues](https://github.com/Shijas786/Megalaunch/issues)

## 🎯 Example Components

Check out the example components in `app/components/megaeth-components.tsx`:
- `MegaPayProComponent` - Pay fees with tokens
- `MegaCommerceComponent` - Create stores and products
- `MegaPaymentsComponent` - Create payment requests

These components demonstrate how to interact with MegaETH Launch Kit Pro contracts using Reown AppKit and Wagmi.
