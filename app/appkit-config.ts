import { createAppKit } from '@reown/appkit/react'
import { WagmiAdapter } from '@reown/appkit-adapter-wagmi'
import { mainnet, arbitrum, polygon, optimism, base } from 'wagmi/chains'

// Get projectId from https://cloud.reown.com
export const projectId = process.env.NEXT_PUBLIC_REOWN_PROJECT_ID || 'YOUR_PROJECT_ID'

if (!projectId) {
  throw new Error('Project ID is not set. Please set NEXT_PUBLIC_REOWN_PROJECT_ID in your .env file')
}

// Create a metadata object - this will be shown in the wallet when connecting
const metadata = {
  name: 'MegaETH Launch Kit Pro',
  description: 'Professional enterprise-grade toolkit for building MegaETH-powered applications',
  url: 'https://megaeth.org',
  icons: ['https://megaeth.org/logo.png']
}

// Create Wagmi Adapter
const wagmiAdapter = new WagmiAdapter({
  chains: [mainnet, arbitrum, polygon, optimism, base],
  projectId
})

// Create the modal
export const appKit = createAppKit({
  adapters: [wagmiAdapter],
  projectId,
  metadata,
  features: {
    analytics: true,
    email: true,
    socials: ['google', 'x', 'github', 'discord', 'apple', 'facebook']
  }
})
