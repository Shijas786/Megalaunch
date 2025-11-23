import { MegaPayProComponent, MegaCommerceComponent, MegaPaymentsComponent } from './components/megaeth-components'

export default function Home() {
  return (
    <div className="space-y-8">
      <div className="text-center">
        <h1 className="text-4xl font-bold text-gray-900 mb-4">
          MegaETH Launch Kit Pro
        </h1>
        <p className="text-xl text-gray-600">
          Professional enterprise-grade toolkit powered by Reown AppKit
        </p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        <MegaPayProComponent />
        <MegaCommerceComponent />
        <MegaPaymentsComponent />
      </div>

      <div className="mt-8 p-6 bg-white rounded-lg shadow-md">
        <h2 className="text-2xl font-bold mb-4">About MegaETH Launch Kit Pro</h2>
        <p className="text-gray-600 mb-4">
          This application demonstrates the integration of Reown AppKit with MegaETH Launch Kit Pro,
          providing seamless wallet connectivity and interaction with our professional smart contracts.
        </p>
        <div className="space-y-2">
          <h3 className="font-semibold">Features:</h3>
          <ul className="list-disc list-inside text-gray-600 space-y-1">
            <li>Multi-wallet support via Reown AppKit</li>
            <li>Cross-chain compatibility (Ethereum, Polygon, Arbitrum, Optimism, Base)</li>
            <li>Professional smart contract interactions</li>
            <li>Enterprise-grade security</li>
            <li>Real-time transaction tracking</li>
          </ul>
        </div>
      </div>
    </div>
  )
}
