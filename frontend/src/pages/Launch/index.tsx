import { zodResolver } from '@hookform/resolvers/zod'
import { useAccount, useContractWrite, useExplorer } from '@starknet-react/core'
import { Wallet, X } from 'lucide-react'
import { useCallback, useState } from 'react'
import { useFieldArray, useForm } from 'react-hook-form'
import { IconButton, PrimaryButton, SecondaryButton } from 'src/components/Button'
import Input from 'src/components/Input'
import NumericalInput from 'src/components/Input/NumericalInput'
import { TOKEN_CLASS_HASH, UDC } from 'src/constants/contracts'
import { MAX_HOLDERS_PER_DEPLOYMENT } from 'src/constants/misc'
import { useDeploymentStore } from 'src/hooks/useDeployment'
import Box from 'src/theme/components/Box'
import { Column, Row } from 'src/theme/components/Flex'
import * as Text from 'src/theme/components/Text'
import { isValidL2Address } from 'src/utils/address'
import { parseFormatedAmount } from 'src/utils/amount'
import { CallData, hash, stark, uint256 } from 'starknet'
import { z } from 'zod'

import * as styles from './style.css'

// zod schemes

const address = z.string().refine((address) => isValidL2Address(address), { message: 'Invalid Starknet address' })

const currencyInput = z.string().refine((input) => +parseFormatedAmount(input) > 0, { message: 'Invalid amount' })

const holder = z.object({
  address,
  amount: currencyInput,
})

const schema = z.object({
  name: z.string().min(1),
  symbol: z.string().min(1),
  initialRecipientAddress: address,
  ownerAddress: address,
  initialSupply: currencyInput,
  holders: z.array(holder),
})

/**
 * LaunchPage component
 */

export default function LaunchPage() {
  const [deployedToken, setDeployedToken] = useState<{ address: string; tx: string } | undefined>(undefined)
  const { pushDeployedContract } = useDeploymentStore()

  const explorer = useExplorer()
  const { account, address } = useAccount()
  const { writeAsync, isPending, reset: resetWrite } = useContractWrite({})

  // If you need the transaction status, you can use this hook.
  // Notice that RPC providers will take some time to receive the transaction,
  // so you will get a "transaction not found" for a few sounds after deployment.
  // const {} = useWaitForTransaction({ hash: deployedToken?.address })

  const {
    control,
    register,
    handleSubmit,
    setValue,
    formState: { errors },
    reset: resetForm,
  } = useForm<z.infer<typeof schema>>({
    resolver: zodResolver(schema),
  })

  const { fields, append, remove } = useFieldArray({
    control,
    name: 'holders',
  })

  const deployToken = useCallback(
    async (data: z.infer<typeof schema>) => {
      if (!account?.address) return

      const salt = stark.randomAddress()
      const unique = 0

      const ctorCalldata = CallData.compile([
        data.ownerAddress,
        data.initialRecipientAddress,
        data.name,
        data.symbol,
        uint256.bnToUint256(BigInt(parseFormatedAmount(data.initialSupply))),
      ])

      // Token address. Used to transfer tokens to initial holders.
      const tokenAddress = hash.calculateContractAddressFromHash(salt, TOKEN_CLASS_HASH, ctorCalldata, unique)

      const deploy = {
        contractAddress: UDC.ADDRESS,
        entrypoint: UDC.ENTRYPOINT,
        calldata: [TOKEN_CLASS_HASH, salt, unique, ctorCalldata.length, ...ctorCalldata],
      }

      const transfers = data.holders.map(({ address, amount }) => ({
        contractAddress: tokenAddress,
        entrypoint: 'transfer',
        calldata: CallData.compile([address, uint256.bnToUint256(BigInt(parseFormatedAmount(amount)))]),
      }))

      try {
        const response = await writeAsync({
          calls: [deploy, ...transfers],
        })

        setDeployedToken({ address: tokenAddress, tx: response.transaction_hash })

        pushDeployedContract(tokenAddress)
      } catch (err) {
        console.error(err)
      }
    },
    [account, writeAsync, pushDeployedContract]
  )

  const restart = useCallback(() => {
    resetWrite()
    resetForm()
    setDeployedToken(undefined)
  }, [resetForm, resetWrite, setDeployedToken])

  return (
    <Row className={styles.wrapper}>
      <Box className={styles.container}>
        <Box as="form" onSubmit={handleSubmit(deployToken)}>
          <Column gap="20">
            <Column gap="4">
              <Text.Body className={styles.inputLabel}>Name</Text.Body>

              <Input placeholder="Unruggable" {...register('name')} />

              <Box className={styles.errorContainer}>
                {errors.name?.message ? <Text.Error>{errors.name.message}</Text.Error> : null}
              </Box>
            </Column>

            <Column gap="4">
              <Text.Body className={styles.inputLabel}>Symbol</Text.Body>

              <Input placeholder="MEME" {...register('symbol')} />

              <Box className={styles.errorContainer}>
                {errors.symbol?.message ? <Text.Error>{errors.symbol.message}</Text.Error> : null}
              </Box>
            </Column>

            <Column gap="4">
              <Text.Body className={styles.inputLabel}>Initial Recipient Address</Text.Body>

              <Input
                placeholder="0x000000000000000000"
                addon={
                  <IconButton
                    type="button"
                    disabled={!address}
                    onClick={() =>
                      address ? setValue('initialRecipientAddress', address, { shouldValidate: true }) : null
                    }
                  >
                    <Wallet />
                  </IconButton>
                }
                {...register('initialRecipientAddress')}
              />

              <Box className={styles.errorContainer}>
                {errors.initialRecipientAddress?.message ? (
                  <Text.Error>{errors.initialRecipientAddress.message}</Text.Error>
                ) : null}
              </Box>
            </Column>

            <Column gap="4">
              <Text.Body className={styles.inputLabel}>Owner Address</Text.Body>

              <Input
                placeholder="0x000000000000000000"
                addon={
                  <IconButton
                    type="button"
                    disabled={!address}
                    onClick={() => (address ? setValue('ownerAddress', address, { shouldValidate: true }) : null)}
                  >
                    <Wallet />
                  </IconButton>
                }
                {...register('ownerAddress')}
              />

              <Box className={styles.errorContainer}>
                {errors.ownerAddress?.message ? <Text.Error>{errors.ownerAddress.message}</Text.Error> : null}
              </Box>
            </Column>

            <Column gap="4">
              <Text.Body className={styles.inputLabel}>Initial Supply</Text.Body>

              <NumericalInput placeholder="10,000,000,000.00" {...register('initialSupply')} />

              <Box className={styles.errorContainer}>
                {errors.initialSupply?.message ? <Text.Error>{errors.initialSupply.message}</Text.Error> : null}
              </Box>
            </Column>

            {fields.map((field, index) => (
              <Column gap="4" key={field.id}>
                <Text.Body className={styles.inputLabel}>Holder {index + 1}</Text.Body>

                <Column gap="2" flexDirection="row">
                  <Input placeholder="Holder address" {...register(`holders.${index}.address`)} />

                  <NumericalInput placeholder="Tokens" {...register(`holders.${index}.amount`)} />

                  <IconButton type="button" onClick={() => remove(index)}>
                    <X />
                  </IconButton>
                </Column>

                <Box className={styles.errorContainer}>
                  {errors.holders?.[index]?.address?.message ? (
                    <Text.Error>{errors.holders?.[index]?.address?.message}</Text.Error>
                  ) : null}

                  {errors.holders?.[index]?.amount?.message ? (
                    <Text.Error>{errors.holders?.[index]?.amount?.message}</Text.Error>
                  ) : null}
                </Box>
              </Column>
            ))}

            {fields.length < MAX_HOLDERS_PER_DEPLOYMENT && (
              <SecondaryButton
                type="button"
                onClick={() => append({ address: '', amount: '' }, { shouldFocus: false })}
              >
                Add holder
              </SecondaryButton>
            )}

            <div />

            {deployedToken ? (
              <Column gap="4">
                <Text.HeadlineMedium textAlign="center">Token deployed!</Text.HeadlineMedium>

                <Column gap="2">
                  <Text.Body className={styles.inputLabel}>Token address</Text.Body>
                  <Text.Body className={styles.deployedAddress}>
                    <a href={explorer.contract(deployedToken.address)}>{deployedToken.address}</a>.
                  </Text.Body>
                </Column>

                <Column gap="2">
                  <Text.Body className={styles.inputLabel}>Transaction</Text.Body>
                  <Text.Body className={styles.deployedAddress}>
                    <a href={explorer.transaction(deployedToken.tx)}>{deployedToken.tx}</a>.
                  </Text.Body>
                </Column>

                <PrimaryButton onClick={restart} type="button" className={styles.deployButton}>
                  Start over
                </PrimaryButton>
              </Column>
            ) : (
              <PrimaryButton disabled={!account || isPending} className={styles.deployButton}>
                {account ? (isPending ? 'Waiting for signature' : 'Deploy') : 'Connect wallet'}
              </PrimaryButton>
            )}
          </Column>
        </Box>
      </Box>
    </Row>
  )
}
