'use client'

import { WagmiProvider } from 'wagmi'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { createConfig, http } from 'wagmi'
import { mainnet, arbitrum, polygon, optimism, base } from 'wagmi/chains'
import { injected, walletConnect, coinbaseWallet } from 'wagmi/connectors'
import { appKit } from './appkit-config'
import { ReactNode } from 'react'

const queryClient = new QueryClient()

// Configure wagmi
const config = createConfig({
  chains: [mainnet, arbitrum, polygon, optimism, base],
  connectors: [
    injected(),
    walletConnect({ projectId: process.env.NEXT_PUBLIC_REOWN_PROJECT_ID || '' }),
    coinbaseWallet({ appName: 'MegaETH Launch Kit Pro' })
  ],
  transports: {
    [mainnet.id]: http(),
    [arbitrum.id]: http(),
    [polygon.id]: http(),
    [optimism.id]: http(),
    [base.id]: http()
  }
})

export function AppKitProvider({ children }: { children: ReactNode }) {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        {children}
      </QueryClientProvider>
    </WagmiProvider>
  )
}
