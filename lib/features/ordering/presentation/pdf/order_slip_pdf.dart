import 'dart:typed_data';

import 'package:sarathigrocery/core/utils/bs_date.dart';
import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/customer_order.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/delivery_type.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_status.dart';
import 'package:sarathigrocery/features/sales/presentation/pages/invoice_screen.dart';
import 'package:sarathigrocery/features/sales/presentation/pdf/invoice_pdf.dart';
import 'package:sarathigrocery/features/settings/domain/entities/business_settings.dart';

/// What the customer gets when an order is taken: the bill's layout, but
/// not a bill (no invoice number, nothing booked yet). The real bill is
/// issued on delivery. [paid] (what was collected at the door) is used once
/// the order is delivered, for the fallback slip when the bill can't be
/// found on this device. Order notes and staff names stay off: they're
/// internal.
({String title, List<(String, String)> head, List<(String, String, String)> lines, List<(String, String)> totals, String note}) orderSlipContent(
  CustomerOrder order,
  BusinessSettings seller, {
  double paid = 0,
}) {
  final delivered = order.status == OrderStatus.delivered;
  final vat = seller.vatRegistered;
  final customer = order.customer;
  final address = order.address.isNotEmpty ? order.address : customer.location;
  return (
    title: delivered ? 'Order (Delivered)' : 'Order',
    head: [
      ('Seller', seller.businessName),
      if (seller.businessAddress.isNotEmpty) ('Address', seller.businessAddress),
      if (seller.panNumber.isNotEmpty) ('PAN/VAT No.', seller.panNumber),
      ('Order no.', order.id),
      ('Date', '${formatBs(order.createdDate)} (${formatDate(order.createdDate)})'),
      ('Customer', customer.name),
      if (address.isNotEmpty) ('Customer address', address),
      if (customer.phone.isNotEmpty) ('Phone', customer.phone),
      if (customer.pan.isNotEmpty) ('Customer PAN', customer.pan),
      ('Delivery', order.deliveryType == DeliveryType.delivery ? 'Delivery' : 'Pickup'),
      ('Payment', orderSlipPayment(order, paid)),
    ],
    lines: [
      for (final i in order.items)
        ('${i.product.name}${vat && i.product.vatExempt ? ' (VAT exempt)' : ''}', '${formatQty(i.qty)} ${i.unit} × ${formatNpr(i.price)}', formatNpr(i.lineTotal)),
    ],
    totals: [
      if (vat) ...[
        if (order.exemptAmount > 0) ('Exempt sales', formatNpr(order.exemptAmount)),
        ('Taxable amount', formatNpr(_taxable(order))),
        ('VAT', formatNpr(order.vatAmount)),
      ],
      ('Total', formatNpr(order.total)),
    ],
    note: 'Not a tax invoice.${vat ? ' Tax invoice is issued on delivery.' : ''}',
  );
}

double _taxable(CustomerOrder order) => order.total - order.vatAmount - order.exemptAmount;

/// "Due on delivery" until delivered; then Credit / Part paid / Paid.
String orderSlipPayment(CustomerOrder order, double paid) {
  if (order.status != OrderStatus.delivered) return 'Due on delivery';
  if (paid < 0.005) return 'Credit';
  return paid >= order.total - 0.005 ? 'Paid' : 'Part paid';
}

Future<Uint8List> orderSlipPdf(CustomerOrder order, BusinessSettings seller, {double paid = 0}) {
  final c = orderSlipContent(order, seller, paid: paid);
  final vat = seller.vatRegistered;
  final customer = order.customer;
  final address = order.address.isNotEmpty ? order.address : customer.location;
  return billLayoutPdf(
    seller: seller,
    title: c.title,
    vat: vat,
    left: [
      ('Customer Name', customer.name),
      if (address.isNotEmpty) ('Customer Address', address),
      if (customer.phone.isNotEmpty) ('Phone', customer.phone),
      if (customer.pan.isNotEmpty) ('Customer ${vat ? 'VAT' : 'PAN'} No', customer.pan),
      ('Delivery', order.deliveryType == DeliveryType.delivery ? 'Delivery' : 'Pickup'),
      ('Mode of payment', orderSlipPayment(order, paid)),
    ],
    right: [
      ('Order Date', billDmy(order.createdDate)),
      ('Order Miti', billBsDmy(order.createdDate)),
      ('Order No', order.id),
    ],
    items: [
      for (final i in order.items) (name: '${i.product.name}${vat && i.product.vatExempt ? ' (VAT exempt)' : ''}', qty: i.qty, unit: i.unit, rate: i.price, amount: i.lineTotal),
    ],
    totals: [
      if (vat) ...[
        if (order.exemptAmount > 0) ('Exempt sales', billMoney(order.exemptAmount)),
        ('Taxable amount', billMoney(_taxable(order))),
        ('${formatQty(seller.taxPercent)} % VAT', billMoney(order.vatAmount)),
      ],
      ('Total Amount', billMoney(order.total)),
    ],
    total: order.total,
    remarks: c.note,
  );
}

/// "Ram Stores 2082-07-17 Order O-xxxx.pdf": customer, BS date placed,
/// "Order", order id.
String orderSlipFileName(CustomerOrder order) => pdfFileName([order.customer.name.trim(), fileDay(order.createdDate), 'Order', order.id]);
