'use client'

import { useAccount, useWriteContract, useReadContract, useWaitForTransactionReceipt } from 'wagmi'
import { useState } from 'react'
import { parseEther } from 'viem'

// Contract addresses (update with your deployed contracts)
const MEGA_PAY_PRO_ADDRESS = process.env.NEXT_PUBLIC_MEGA_PAY_PRO_ADDRESS || '0x...'
const MEGA_COMMERCE_ADDRESS = process.env.NEXT_PUBLIC_MEGA_COMMERCE_ADDRESS || '0x...'
const MEGA_PAYMENTS_ADDRESS = process.env.NEXT_PUBLIC_MEGA_PAYMENTS_ADDRESS || '0x...'

// ABI snippets (simplified - use full ABIs from artifacts)
const MEGA_PAY_PRO_ABI = [
  {
    name: 'payFeesWithSignature',
    type: 'function',
    inputs: [
      { name: 'token', type: 'address' },
      { name: 'gasUsed', type: 'uint256' },
      { name: 'nonce', type: 'uint256' },
      { name: 'signature', type: 'bytes' }
    ]
  }
] as const

const MEGA_COMMERCE_ABI = [
  {
    name: 'createStore',
    type: 'function',
    inputs: [
      { name: 'name', type: 'string' },
      { name: 'description', type: 'string' },
      { name: 'logoUrl', type: 'string' }
    ]
  },
  {
    name: 'createProduct',
    type: 'function',
    inputs: [
      { name: 'name', type: 'string' },
      { name: 'description', type: 'string' },
      { name: 'price', type: 'uint256' },
      { name: 'priceToken', type: 'address' },
      { name: 'stock', type: 'uint256' },
      { name: 'imageUrl', type: 'string' }
    ]
  }
] as const

const MEGA_PAYMENTS_ABI = [
  {
    name: 'createPaymentRequest',
    type: 'function',
    inputs: [
      { name: 'customer', type: 'address' },
      { name: 'amount', type: 'uint256' },
      { name: 'token', type: 'address' },
      { name: 'description', type: 'string' },
      { name: 'metadata', type: 'string' },
      { name: 'expiresAt', type: 'uint256' }
    ],
    outputs: [{ name: '', type: 'uint256' }]
  }
] as const

export function MegaPayProComponent() {
  const { address, isConnected } = useAccount()
  const [tokenAddress, setTokenAddress] = useState('')
  const [gasUsed, setGasUsed] = useState('')
  const [nonce, setNonce] = useState(Date.now().toString())

  const { writeContract, data: hash, isPending } = useWriteContract()
  const { isLoading: isConfirming, isSuccess: isConfirmed } = useWaitForTransactionReceipt({
    hash
  })

  const handlePayFees = async () => {
    if (!isConnected || !address) return

    // In production, get signature from backend or signer
    const signature = '0x' // Placeholder - implement proper signature

    writeContract({
      address: MEGA_PAY_PRO_ADDRESS as `0x${string}`,
      abi: MEGA_PAY_PRO_ABI,
      functionName: 'payFeesWithSignature',
      args: [tokenAddress as `0x${string}`, BigInt(gasUsed), BigInt(nonce), signature as `0x${string}`]
    })
  }

  if (!isConnected) {
    return <div className="p-4 bg-yellow-50 rounded-lg">Please connect your wallet</div>
  }

  return (
    <div className="p-6 bg-white rounded-lg shadow-md">
      <h2 className="text-xl font-bold mb-4">MegaPayPro - Pay Fees</h2>
      <div className="space-y-4">
        <div>
          <label className="block text-sm font-medium mb-2">Token Address</label>
          <input
            type="text"
            value={tokenAddress}
            onChange={(e) => setTokenAddress(e.target.value)}
            className="w-full px-4 py-2 border rounded-lg"
            placeholder="0x..."
          />
        </div>
        <div>
          <label className="block text-sm font-medium mb-2">Gas Used</label>
          <input
            type="number"
            value={gasUsed}
            onChange={(e) => setGasUsed(e.target.value)}
            className="w-full px-4 py-2 border rounded-lg"
            placeholder="100000"
          />
        </div>
        <button
          onClick={handlePayFees}
          disabled={isPending || isConfirming}
          className="w-full px-4 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 disabled:opacity-50"
        >
          {isPending ? 'Confirming...' : isConfirming ? 'Processing...' : 'Pay Fees'}
        </button>
        {isConfirmed && <div className="text-green-600">Transaction confirmed!</div>}
      </div>
    </div>
  )
}

export function MegaCommerceComponent() {
  const { address, isConnected } = useAccount()
  const [storeName, setStoreName] = useState('')
  const [productName, setProductName] = useState('')
  const [price, setPrice] = useState('')

  const { writeContract: createStore, isPending: isCreatingStore } = useWriteContract()
  const { writeContract: createProduct, isPending: isCreatingProduct } = useWriteContract()

  const handleCreateStore = async () => {
    if (!isConnected) return

    createStore({
      address: MEGA_COMMERCE_ADDRESS as `0x${string}`,
      abi: MEGA_COMMERCE_ABI,
      functionName: 'createStore',
      args: [storeName, 'My store description', 'https://example.com/logo.png']
    })
  }

  const handleCreateProduct = async () => {
    if (!isConnected) return

    createProduct({
      address: MEGA_COMMERCE_ADDRESS as `0x${string}`,
      abi: MEGA_COMMERCE_ABI,
      functionName: 'createProduct',
      args: [
        productName,
        'Product description',
        parseEther(price),
        '0x0000000000000000000000000000000000000000', // ETH
        BigInt(100),
        'https://example.com/product.png'
      ]
    })
  }

  if (!isConnected) {
    return <div className="p-4 bg-yellow-50 rounded-lg">Please connect your wallet</div>
  }

  return (
    <div className="p-6 bg-white rounded-lg shadow-md">
      <h2 className="text-xl font-bold mb-4">MegaCommerce</h2>
      <div className="space-y-6">
        <div>
          <h3 className="font-semibold mb-2">Create Store</h3>
          <div className="space-y-2">
            <input
              type="text"
              value={storeName}
              onChange={(e) => setStoreName(e.target.value)}
              className="w-full px-4 py-2 border rounded-lg"
              placeholder="Store Name"
            />
            <button
              onClick={handleCreateStore}
              disabled={isCreatingStore}
              className="px-4 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 disabled:opacity-50"
            >
              {isCreatingStore ? 'Creating...' : 'Create Store'}
            </button>
          </div>
        </div>
        <div>
          <h3 className="font-semibold mb-2">Create Product</h3>
          <div className="space-y-2">
            <input
              type="text"
              value={productName}
              onChange={(e) => setProductName(e.target.value)}
              className="w-full px-4 py-2 border rounded-lg"
              placeholder="Product Name"
            />
            <input
              type="text"
              value={price}
              onChange={(e) => setPrice(e.target.value)}
              className="w-full px-4 py-2 border rounded-lg"
              placeholder="Price (ETH)"
            />
            <button
              onClick={handleCreateProduct}
              disabled={isCreatingProduct}
              className="px-4 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 disabled:opacity-50"
            >
              {isCreatingProduct ? 'Creating...' : 'Create Product'}
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}

export function MegaPaymentsComponent() {
  const { address, isConnected } = useAccount()
  const [customerAddress, setCustomerAddress] = useState('')
  const [amount, setAmount] = useState('')
  const [description, setDescription] = useState('')

  const { writeContract, data: hash, isPending } = useWriteContract()
  const { isLoading: isConfirming, isSuccess: isConfirmed } = useWaitForTransactionReceipt({
    hash
  })

  const handleCreatePaymentRequest = async () => {
    if (!isConnected) return

    const expiresAt = BigInt(Math.floor(Date.now() / 1000) + 24 * 60 * 60) // 24 hours

    writeContract({
      address: MEGA_PAYMENTS_ADDRESS as `0x${string}`,
      abi: MEGA_PAYMENTS_ABI,
      functionName: 'createPaymentRequest',
      args: [
        customerAddress as `0x${string}`,
        parseEther(amount),
        '0x0000000000000000000000000000000000000000', // ETH
        description,
        '{}',
        expiresAt
      ]
    })
  }

  if (!isConnected) {
    return <div className="p-4 bg-yellow-50 rounded-lg">Please connect your wallet</div>
  }

  return (
    <div className="p-6 bg-white rounded-lg shadow-md">
      <h2 className="text-xl font-bold mb-4">MegaPayments - Create Payment Request</h2>
      <div className="space-y-4">
        <div>
          <label className="block text-sm font-medium mb-2">Customer Address</label>
          <input
            type="text"
            value={customerAddress}
            onChange={(e) => setCustomerAddress(e.target.value)}
            className="w-full px-4 py-2 border rounded-lg"
            placeholder="0x..."
          />
        </div>
        <div>
          <label className="block text-sm font-medium mb-2">Amount (ETH)</label>
          <input
            type="text"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            className="w-full px-4 py-2 border rounded-lg"
            placeholder="0.1"
          />
        </div>
        <div>
          <label className="block text-sm font-medium mb-2">Description</label>
          <input
            type="text"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            className="w-full px-4 py-2 border rounded-lg"
            placeholder="Payment for services"
          />
        </div>
        <button
          onClick={handleCreatePaymentRequest}
          disabled={isPending || isConfirming}
          className="w-full px-4 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 disabled:opacity-50"
        >
          {isPending ? 'Confirming...' : isConfirming ? 'Processing...' : 'Create Payment Request'}
        </button>
        {isConfirmed && <div className="text-green-600">Payment request created!</div>}
      </div>
    </div>
  )
}
