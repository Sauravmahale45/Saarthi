import 'package:flutter/material.dart';
import '../services/wallet_service.dart';

class WithdrawalForm extends StatefulWidget {
  final String userId;
  final String userName;
  final double availableBalance;
  final Function(Map<String, dynamic>) onSubmit;

  const WithdrawalForm({
    super.key,
    required this.userId,
    required this.userName,
    required this.availableBalance,
    required this.onSubmit,
  });

  @override
  State<WithdrawalForm> createState() => _WithdrawalFormState();
}

class _WithdrawalFormState extends State<WithdrawalForm> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _upiController = TextEditingController();
  bool _isLoading = false;

  final WalletService _walletService = WalletService();

  @override
  void dispose() {
    _amountController.dispose();
    _upiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Center(
              child: Text(
                'Withdraw Money',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Available Balance: ${WalletService.formatCurrency(widget.availableBalance)}',
                style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
              ),
            ),
            const SizedBox(height: 24),

            // Amount field
            TextFormField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Amount to withdraw',
                prefixText: '₹ ',
                prefixIcon: const Icon(Icons.currency_rupee, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFF4F46E5),
                    width: 2,
                  ),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFEF4444)),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter amount';
                }
                final amount = double.tryParse(value);
                if (amount == null) {
                  return 'Please enter a valid number';
                }
                if (amount <= 0) {
                  return 'Amount must be greater than 0';
                }
                if (amount > widget.availableBalance) {
                  return 'Insufficient balance';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // UPI ID field
            TextFormField(
              controller: _upiController,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(
                labelText: 'UPI ID',
                hintText: 'yourname@okhdfcbank',
                prefixIcon: const Icon(Icons.payment, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFF4F46E5),
                    width: 2,
                  ),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter UPI ID';
                }
                // Basic UPI validation
                if (!value.contains('@')) {
                  return 'Please enter a valid UPI ID';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),

            // Quick amount suggestions
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildQuickAmountChip(100),
                  _buildQuickAmountChip(500),
                  _buildQuickAmountChip(1000),
                  _buildQuickAmountChip(2000),
                  _buildQuickAmountChip(5000),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Submit button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submitWithdrawal,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Request Withdrawal',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),

            // Info text
            Center(
              child: Text(
                'Withdrawals are processed within 2-3 business days',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAmountChip(double amount) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text('₹ ${amount.toInt()}'),
        selected: false,
        onSelected: (_) {
          setState(() {
            _amountController.text = amount.toString();
          });
        },
        backgroundColor: Colors.grey.shade100,
        selectedColor: const Color(0xFF4F46E5).withOpacity(0.1),
        checkmarkColor: const Color(0xFF4F46E5),
        labelStyle: TextStyle(
          color: _amountController.text == amount.toString()
              ? const Color(0xFF4F46E5)
              : const Color(0xFF0F172A),
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: _amountController.text == amount.toString()
                ? const Color(0xFF4F46E5)
                : Colors.grey.shade300,
          ),
        ),
      ),
    );
  }

  Future<void> _submitWithdrawal() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final amount = double.parse(_amountController.text);
    final result = await _walletService.requestWithdrawal(
      userId: widget.userId,
      userName: widget.userName,
      amount: amount,
      upiId: _upiController.text.trim(),
    );

    if (mounted) {
      setState(() => _isLoading = false);
      widget.onSubmit(result);

      if (result['success'] == true) {
        Navigator.pop(context);
      }
    }
  }
}
